package main

import (
	"compress/gzip"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const nixBase32Alphabet = "0123456789abcdfghijklmnpqrsvwxyz"

type narInfo struct {
	storePath   string
	url         string
	compression string
	narHash     string
	narSize     int64
	fileHash    string
	fileSize    int64
	references  []string
	signatures  []string
}

func main() {
	if len(os.Args) == 2 && (os.Args[1] == "--help" || os.Args[1] == "-h") {
		fmt.Println("Usage: nixpp fetch --cache URL --store-path /nix/store/HASH-name --destination DIR --public-key NAME:BASE64")
		os.Exit(0)
	}
	if len(os.Args) < 2 || os.Args[1] != "fetch" {
		fmt.Fprintln(os.Stderr, "Usage: nixpp fetch --cache URL --store-path /nix/store/HASH-name --destination DIR --public-key NAME:BASE64")
		os.Exit(2)
	}
	if err := fetch(os.Args[2:]); err != nil {
		fmt.Fprintln(os.Stderr, "nixpp:", err)
		os.Exit(1)
	}
}

func fetch(args []string) error {
	flags := flag.NewFlagSet("fetch", flag.ContinueOnError)
	cache := flags.String("cache", "", "Nix binary cache URL")
	storePath := flags.String("store-path", "", "full Nix store path")
	destination := flags.String("destination", "", "new directory to create from the cache output")
	publicKey := flags.String("public-key", "", "trusted Nix cache key NAME:BASE64")
	netrcFile := flags.String("netrc-file", "", "curl netrc file for authenticated cache access")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *cache == "" || *storePath == "" || *destination == "" || *publicKey == "" || flags.NArg() != 0 {
		return errors.New("cache, store-path, destination, and public-key are required")
	}
	storeHash, _, ok := strings.Cut(strings.TrimPrefix(*storePath, "/nix/store/"), "-")
	if !ok || len(storeHash) != 32 || strings.Contains(*storePath, "..") || !strings.HasPrefix(*storePath, "/nix/store/") {
		return errors.New("invalid full Nix store path")
	}
	base, err := url.Parse(*cache)
	if err != nil || (base.Scheme != "https" && base.Scheme != "http") || base.Host == "" || base.User != nil || base.RawQuery != "" || base.Fragment != "" {
		return errors.New("cache must be an HTTP(S) URL")
	}
	if base.Scheme != "https" && (os.Getenv("NIXPP_USERNAME") != "" || *netrcFile != "") {
		return errors.New("refusing to send cache credentials over plain HTTP")
	}
	netrcPath := *netrcFile
	cleanup := func() {}
	if netrcPath != "" {
		if err := validateNetrc(netrcPath); err != nil {
			return err
		}
	} else {
		netrcPath, cleanup, err = makeNetrc(base.Hostname())
		if err != nil {
			return err
		}
	}
	defer cleanup()
	infoURL := *base
	infoURL.Path = strings.TrimRight(infoURL.Path, "/") + "/" + storeHash + ".narinfo"
	info, err := curlRead(infoURL.String(), netrcPath, 1<<20)
	if err != nil {
		return fmt.Errorf("fetch narinfo: %w", err)
	}
	metadata, err := parseNarInfo(info)
	if err != nil {
		return err
	}
	if metadata.storePath != *storePath {
		return errors.New("narinfo StorePath does not match requested store path")
	}
	if len(metadata.references) != 0 {
		return errors.New("refusing cache output with Nix store references")
	}
	if err := verifySignature(metadata, *publicKey); err != nil {
		return err
	}
	if metadata.compression != "none" && metadata.compression != "gzip" && metadata.compression != "xz" {
		return fmt.Errorf("unsupported cache compression %q (nixpp supports none, gzip, and xz)", metadata.compression)
	}
	archiveURL, err := safeCacheURL(base, metadata.url)
	if err != nil {
		return err
	}
	return downloadAndExtract(archiveURL, netrcPath, metadata, *destination)
}

func validateNetrc(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("cannot read netrc file: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 {
		return errors.New("netrc file must be a regular file with permissions 0600 or stricter")
	}
	return nil
}

func makeNetrc(host string) (string, func(), error) {
	username, usernameSet := os.LookupEnv("NIXPP_USERNAME")
	password, passwordSet := os.LookupEnv("NIXPP_PASSWORD")
	if !usernameSet && !passwordSet {
		return "", func() {}, nil
	}
	if !usernameSet || !passwordSet {
		return "", nil, errors.New("NIXPP_USERNAME and NIXPP_PASSWORD must be set together")
	}
	file, err := os.CreateTemp("", "nixpp-netrc-*")
	if err != nil {
		return "", nil, err
	}
	path := file.Name()
	if err := file.Chmod(0600); err != nil {
		file.Close()
		os.Remove(path)
		return "", nil, err
	}
	content := fmt.Sprintf("machine %s login %s password %s\n", host, netrcQuote(username), netrcQuote(password))
	if _, err := io.WriteString(file, content); err != nil {
		file.Close()
		os.Remove(path)
		return "", nil, err
	}
	if err := file.Close(); err != nil {
		os.Remove(path)
		return "", nil, err
	}
	return path, func() { _ = os.Remove(path) }, nil
}

func netrcQuote(value string) string {
	value = strings.ReplaceAll(value, "\\", "\\\\")
	value = strings.ReplaceAll(value, "\"", "\\\"")
	value = strings.ReplaceAll(value, "\n", "")
	value = strings.ReplaceAll(value, "\r", "")
	return "\"" + value + "\""
}

func curlArgs(netrcPath string, progress bool) []string {
	arguments := []string{"--fail", "--show-error", "--location", "--proto", "=https,http", "--max-time", "7200"}
	if progress && stderrIsTerminal() {
		arguments = append(arguments, "--progress-bar")
	} else {
		arguments = append(arguments, "--silent")
	}
	if netrcPath != "" {
		arguments = append(arguments, "--netrc-file", netrcPath)
	}
	return arguments
}

func curlRead(rawURL, netrcPath string, maxSize int64) ([]byte, error) {
	arguments := curlArgs(netrcPath, false)
	arguments = append(arguments, "--max-filesize", strconv.FormatInt(maxSize, 10), "--output", "-", rawURL)
	command := exec.Command("curl", arguments...)
	command.Env = childEnvironment()
	data, err := command.Output()
	if err != nil {
		return nil, fmt.Errorf("curl failed fetching %s: %w", rawURL, err)
	}
	if int64(len(data)) > maxSize {
		return nil, errors.New("narinfo response exceeds 1 MiB safety limit")
	}
	return data, nil
}

func childEnvironment() []string {
	environment := make([]string, 0, len(os.Environ()))
	for _, value := range os.Environ() {
		if strings.HasPrefix(value, "NIXPP_USERNAME=") || strings.HasPrefix(value, "NIXPP_PASSWORD=") {
			continue
		}
		environment = append(environment, value)
	}
	return environment
}

func stderrIsTerminal() bool {
	info, err := os.Stderr.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

func parseNarInfo(data []byte) (narInfo, error) {
	var info narInfo
	fields := make(map[string][]string)
	for _, line := range strings.Split(string(data), "\n") {
		if line == "" {
			continue
		}
		key, value, ok := strings.Cut(line, ": ")
		if !ok {
			return info, fmt.Errorf("malformed narinfo line %q", line)
		}
		fields[key] = append(fields[key], value)
	}
	field := func(key string) (string, error) {
		values := fields[key]
		if len(values) != 1 {
			return "", fmt.Errorf("narinfo must contain exactly one %s field", key)
		}
		return values[0], nil
	}
	var err error
	if info.storePath, err = field("StorePath"); err != nil {
		return info, err
	}
	if info.url, err = field("URL"); err != nil {
		return info, err
	}
	info.compression = "bzip2"
	if values := fields["Compression"]; len(values) > 0 {
		if len(values) != 1 {
			return info, errors.New("narinfo has duplicate Compression fields")
		}
		info.compression = values[0]
	}
	if info.narHash, err = field("NarHash"); err != nil {
		return info, err
	}
	size, err := field("NarSize")
	if err != nil {
		return info, err
	}
	if info.narSize, err = strconv.ParseInt(size, 10, 64); err != nil || info.narSize <= 0 || info.narSize > 20<<30 {
		return info, errors.New("invalid NarSize")
	}
	if values := fields["References"]; len(values) != 1 {
		return info, errors.New("narinfo must contain exactly one References field")
	} else if values[0] != "" {
		info.references = strings.Fields(values[0])
	}
	info.signatures = fields["Sig"]
	if values := fields["FileHash"]; len(values) > 1 {
		return info, errors.New("narinfo has duplicate FileHash fields")
	} else if len(values) == 1 {
		info.fileHash = values[0]
	}
	if values := fields["FileSize"]; len(values) > 1 {
		return info, errors.New("narinfo has duplicate FileSize fields")
	} else if len(values) == 1 {
		if info.fileSize, err = strconv.ParseInt(values[0], 10, 64); err != nil || info.fileSize <= 0 {
			return info, errors.New("invalid FileSize")
		}
		if info.fileSize > info.narSize+(1<<20) {
			return info, errors.New("FileSize exceeds the NAR size safety limit")
		}
	}
	return info, nil
}

func verifySignature(info narInfo, publicKey string) error {
	name, encodedKey, ok := strings.Cut(publicKey, ":")
	if !ok || name == "" {
		return errors.New("public key must use Nix cache format NAME:BASE64")
	}
	key, err := base64.StdEncoding.DecodeString(encodedKey)
	if err != nil || len(key) != ed25519.PublicKeySize {
		return errors.New("invalid Ed25519 cache public key")
	}
	narHash, ok := strings.CutPrefix(info.narHash, "sha256:")
	if !ok {
		return errors.New("narinfo NarHash must use sha256:")
	}
	fingerprint := "1;" + info.storePath + ";sha256:" + narHash + ";" + strconv.FormatInt(info.narSize, 10) + ";"
	refs := append([]string(nil), info.references...)
	sort.Strings(refs)
	fingerprint += strings.Join(refs, ",")
	for _, signature := range info.signatures {
		keyName, encodedSignature, ok := strings.Cut(signature, ":")
		if !ok || keyName != name {
			continue
		}
		sig, err := base64.StdEncoding.DecodeString(encodedSignature)
		if err == nil && ed25519.Verify(ed25519.PublicKey(key), []byte(fingerprint), sig) {
			return nil
		}
	}
	return errors.New("narinfo has no valid signature from the trusted cache key")
}

func safeCacheURL(base *url.URL, rawPath string) (string, error) {
	if strings.Contains(rawPath, "\\") || strings.Contains(rawPath, "..") || strings.HasPrefix(rawPath, "/") || strings.ContainsAny(rawPath, "?#") {
		return "", errors.New("narinfo URL is not a safe relative path")
	}
	parsed, err := url.Parse(rawPath)
	if err != nil || parsed.IsAbs() || parsed.Host != "" {
		return "", errors.New("narinfo URL is not a safe relative path")
	}
	result := *base
	result.Path = strings.TrimRight(result.Path, "/") + "/" + rawPath
	return result.String(), nil
}

func downloadAndExtract(rawURL, netrcPath string, info narInfo, destination string) error {
	if _, err := os.Lstat(destination); err == nil {
		return fmt.Errorf("destination already exists: %s", destination)
	} else if !os.IsNotExist(err) {
		return err
	}
	parent := filepath.Dir(destination)
	if err := os.MkdirAll(parent, 0700); err != nil {
		return err
	}
	stage, err := os.MkdirTemp(parent, ".nixpp-stage-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)

	compressedLimit := info.fileSize
	if compressedLimit == 0 {
		compressedLimit = info.narSize + 1<<20
	}
	downloadPath := filepath.Join(stage, "download")
	arguments := curlArgs(netrcPath, true)
	arguments = append(arguments, "--max-filesize", strconv.FormatInt(compressedLimit, 10), "--output", downloadPath, rawURL)
	command := exec.Command("curl", arguments...)
	command.Env = childEnvironment()
	if stderrIsTerminal() {
		command.Stderr = os.Stderr
		if err := command.Run(); err != nil {
			return fmt.Errorf("curl failed fetching NAR: %w", err)
		}
	} else if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("curl failed fetching NAR: %w: %s", err, strings.TrimSpace(string(output)))
	}
	compressed, err := os.Open(downloadPath)
	if err != nil {
		return err
	}
	fileHasher := sha256.New()
	compressedSize, err := io.Copy(fileHasher, compressed)
	closeErr := compressed.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if info.fileSize != 0 && compressedSize != info.fileSize {
		return errors.New("downloaded NAR file size mismatch")
	}
	if info.fileSize == 0 && compressedSize > compressedLimit {
		return errors.New("compressed NAR exceeds safety limit")
	}
	if info.fileHash != "" {
		expected, err := decodeNixHash(info.fileHash)
		if err != nil || !equalBytes(fileHasher.Sum(nil), expected) {
			return errors.New("downloaded NAR file hash mismatch")
		}
	}
	reader, closeReader, err := openDecompressor(info.compression, downloadPath)
	if err != nil {
		return err
	}
	narFile, err := os.Create(filepath.Join(stage, "archive.nar"))
	if err != nil {
		_ = closeReader()
		return err
	}
	narHasher := sha256.New()
	narSize, err := io.Copy(io.MultiWriter(narFile, narHasher), io.LimitReader(reader, info.narSize+1))
	readerErr := closeReader()
	closeErr = narFile.Close()
	if err != nil {
		return err
	}
	if readerErr != nil {
		return readerErr
	}
	if closeErr != nil {
		return closeErr
	}
	if narSize != info.narSize {
		return errors.New("uncompressed NAR size mismatch")
	}
	expected, err := decodeNixHash(info.narHash)
	if err != nil || !equalBytes(narHasher.Sum(nil), expected) {
		return errors.New("NAR hash mismatch")
	}
	archive, err := os.Open(filepath.Join(stage, "archive.nar"))
	if err != nil {
		return err
	}
	output := filepath.Join(stage, "output")
	if err := extractNAR(archive, output); err != nil {
		archive.Close()
		return err
	}
	if err := archive.Close(); err != nil {
		return err
	}
	if err := os.Remove(filepath.Join(stage, "download")); err != nil {
		return err
	}
	if err := os.Remove(filepath.Join(stage, "archive.nar")); err != nil {
		return err
	}
	if err := os.Rename(filepath.Join(stage, "output"), destination); err != nil {
		return err
	}
	return nil
}

func openDecompressor(compression, path string) (io.Reader, func() error, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, nil, err
	}
	switch compression {
	case "none":
		return file, file.Close, nil
	case "gzip":
		reader, err := gzip.NewReader(file)
		if err != nil {
			file.Close()
			return nil, nil, err
		}
		return reader, func() error {
			readerErr := reader.Close()
			fileErr := file.Close()
			if readerErr != nil {
				return readerErr
			}
			return fileErr
		}, nil
	case "xz":
		file.Close()
		command := exec.Command("xz", "-dc", "--", path)
		stdout, err := command.StdoutPipe()
		if err != nil {
			return nil, nil, err
		}
		var stderr strings.Builder
		command.Stderr = &stderr
		if err := command.Start(); err != nil {
			return nil, nil, err
		}
		return stdout, func() error {
			if err := stdout.Close(); err != nil {
				command.Process.Kill()
				_ = command.Wait()
				return err
			}
			if err := command.Wait(); err != nil {
				return fmt.Errorf("xz decompression failed: %w: %s", err, strings.TrimSpace(stderr.String()))
			}
			return nil
		}, nil
	default:
		file.Close()
		return nil, nil, fmt.Errorf("unsupported compression %q", compression)
	}
}

func decodeNixHash(value string) ([]byte, error) {
	algorithm, encoded, ok := strings.Cut(value, ":")
	if !ok || algorithm != "sha256" {
		return nil, errors.New("expected sha256 Nix hash")
	}
	return nixBase32Decode(encoded)
}

func nixBase32Decode(value string) ([]byte, error) {
	if len(value) != 52 {
		return nil, errors.New("invalid Nix base32 SHA-256 length")
	}
	out := make([]byte, 32)
	for n := 0; n < len(value); n++ {
		char := strings.IndexByte(nixBase32Alphabet, value[n])
		if char < 0 {
			return nil, errors.New("invalid Nix base32 digit")
		}
		bit := (len(value) - 1 - n) * 5
		byteIndex := bit / 8
		shift := bit % 8
		if byteIndex < len(out) {
			out[byteIndex] |= byte(char << shift)
		}
		if shift > 3 && byteIndex+1 < len(out) {
			out[byteIndex+1] |= byte(char >> (8 - shift))
		}
	}
	encoded, err := nixBase32Encode(out)
	if err != nil || encoded != value {
		return nil, errors.New("non-canonical Nix base32 SHA-256")
	}
	return out, nil
}

func nixBase32Encode(digest []byte) (string, error) {
	if len(digest) != sha256.Size {
		return "", errors.New("Nix base32 encoding requires a SHA-256 digest")
	}
	length := (len(digest)*8-1)/5 + 1
	var output strings.Builder
	for n := length - 1; n >= 0; n-- {
		bit := n * 5
		index := bit / 8
		shift := bit % 8
		value := int(digest[index]) >> shift
		if shift > 3 && index+1 < len(digest) {
			value |= int(digest[index+1]) << (8 - shift)
		}
		output.WriteByte(nixBase32Alphabet[value&0x1f])
	}
	return output.String(), nil
}

func equalBytes(left, right []byte) bool {
	if len(left) != len(right) {
		return false
	}
	var different byte
	for i := range left {
		different |= left[i] ^ right[i]
	}
	return different == 0
}

type narReader struct {
	r io.Reader
}

func (reader narReader) string() ([]byte, error) {
	var encoded [8]byte
	if err := readFull(reader.r, encoded[:]); err != nil {
		return nil, err
	}
	length := binary.LittleEndian.Uint64(encoded[:])
	if length > 1<<30 {
		return nil, errors.New("NAR string exceeds 1 GiB limit")
	}
	value := make([]byte, int(length))
	if err := readFull(reader.r, value); err != nil {
		return nil, err
	}
	if padding := (8 - length%8) % 8; padding > 0 {
		if err := discardPadding(reader.r, int(padding)); err != nil {
			return nil, err
		}
	}
	return value, nil
}

func (reader narReader) expect(value string) error {
	actual, err := reader.string()
	if err != nil {
		return err
	}
	if string(actual) != value {
		return fmt.Errorf("invalid NAR token %q, expected %q", actual, value)
	}
	return nil
}

func readFull(reader io.Reader, buffer []byte) error {
	_, err := io.ReadFull(reader, buffer)
	return err
}

func discardPadding(reader io.Reader, size int) error {
	var padding [8]byte
	return readFull(reader, padding[:size])
}

func extractNAR(reader io.Reader, destination string) error {
	nar := narReader{r: reader}
	if err := nar.expect("nix-archive-1"); err != nil {
		return err
	}
	if err := extractNode(nar, destination, destination); err != nil {
		return err
	}
	var trailing [1]byte
	if count, err := reader.Read(trailing[:]); err != io.EOF || count != 0 {
		return errors.New("unexpected data after NAR root node")
	}
	return nil
}

func extractNode(nar narReader, root, path string) error {
	if err := nar.expect("("); err != nil {
		return err
	}
	if err := nar.expect("type"); err != nil {
		return err
	}
	kind, err := nar.string()
	if err != nil {
		return err
	}
	switch string(kind) {
	case "directory":
		if err := os.Mkdir(path, 0755); err != nil {
			return err
		}
		for {
			entry, err := nar.string()
			if err != nil {
				return err
			}
			if string(entry) == ")" {
				return nil
			}
			if string(entry) != "entry" {
				return errors.New("invalid NAR directory entry")
			}
			if err := nar.expect("("); err != nil {
				return err
			}
			if err := nar.expect("name"); err != nil {
				return err
			}
			name, err := nar.string()
			if err != nil {
				return err
			}
			if err := validEntryName(name); err != nil {
				return err
			}
			if err := nar.expect("node"); err != nil {
				return err
			}
			if err := extractNode(nar, root, filepath.Join(path, string(name))); err != nil {
				return err
			}
			if err := nar.expect(")"); err != nil {
				return err
			}
		}
	case "regular":
		executable := false
		value, err := nar.string()
		if err != nil {
			return err
		}
		if string(value) == "executable" {
			executable = true
			if err := nar.expect(""); err != nil {
				return err
			}
			if value, err = nar.string(); err != nil {
				return err
			}
		}
		if string(value) != "contents" {
			return errors.New("invalid NAR regular file")
		}
		if err := writeNARFile(nar, path, executable); err != nil {
			return err
		}
		return nar.expect(")")
	case "symlink":
		if err := nar.expect("target"); err != nil {
			return err
		}
		target, err := nar.string()
		if err != nil {
			return err
		}
		if err := safeSymlink(root, path, string(target)); err != nil {
			return err
		}
		if err := os.Symlink(string(target), path); err != nil {
			return err
		}
		return nar.expect(")")
	default:
		return fmt.Errorf("unsupported NAR node type %q", kind)
	}
}

func validEntryName(name []byte) error {
	if len(name) == 0 || string(name) == "." || string(name) == ".." || strings.ContainsAny(string(name), "/\\\x00") {
		return fmt.Errorf("unsafe NAR entry name %q", name)
	}
	return nil
}

func safeSymlink(root, path, target string) error {
	if target == "" || filepath.IsAbs(target) || strings.ContainsRune(target, '\x00') {
		return errors.New("NAR has an absolute or empty symlink target")
	}
	resolved := filepath.Clean(filepath.Join(filepath.Dir(path), target))
	root = filepath.Clean(root)
	if !strings.HasPrefix(resolved, root+string(os.PathSeparator)) && resolved != root {
		return errors.New("NAR symlink escapes output tree")
	}
	return nil
}

func writeNARFile(nar narReader, path string, executable bool) error {
	var encoded [8]byte
	if err := readFull(nar.r, encoded[:]); err != nil {
		return err
	}
	length := binary.LittleEndian.Uint64(encoded[:])
	if length > 1<<40 {
		return errors.New("NAR file exceeds 1 TiB limit")
	}
	mode := os.FileMode(0644)
	if executable {
		mode = 0755
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	_, copyErr := io.CopyN(file, nar.r, int64(length))
	padding := (8 - length%8) % 8
	if copyErr == nil && padding > 0 {
		copyErr = discardPadding(nar.r, int(padding))
	}
	closeErr := file.Close()
	if copyErr != nil {
		return copyErr
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Chmod(path, mode)
}
