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
	"time"
)

const nixBase32Alphabet = "0123456789abcdfghijklmnpqrsvwxyz"

type progressUI struct {
	output io.Writer
	color  bool
}

func newProgressUI(output io.Writer) progressUI {
	color := stderrIsTerminal() && os.Getenv("NO_COLOR") == "" && os.Getenv("TERM") != "dumb"
	return progressUI{output: output, color: color}
}

func (ui progressUI) paint(code, value string) string {
	if !ui.color {
		return value
	}
	return "\x1b[" + code + "m" + value + "\x1b[0m"
}

func (ui progressUI) title() {
	fmt.Fprintf(ui.output, "\n%s %s\n", ui.paint("1;36", "nixpp ✨"), ui.paint("2", "switching Termux environment"))
}

func (ui progressUI) stage(label string, action func() error) error {
	fmt.Fprintf(ui.output, "  %s %s\n", ui.paint("36", "✦"), label)
	started := time.Now()
	if err := action(); err != nil {
		fmt.Fprintf(ui.output, "  %s %s %s\n", ui.paint("1;31", "✗"), ui.paint("31", "Failed"), ui.paint("2", "("+time.Since(started).Round(time.Second).String()+")"))
		return err
	}
	fmt.Fprintf(ui.output, "  %s %s %s\n", ui.paint("1;32", "✓"), ui.paint("32", "Done"), ui.paint("2", "("+time.Since(started).Round(time.Second).String()+")"))
	return nil
}

func (ui progressUI) warning(message string) {
	fmt.Fprintf(ui.output, "  %s %s\n", ui.paint("1;33", "!"), message)
}

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
		printUsage(os.Stdout)
		os.Exit(0)
	}
	if len(os.Args) < 2 {
		printUsage(os.Stderr)
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "fetch":
		err = fetch(os.Args[2:])
	case "switch":
		err = switchProfile(os.Args[2:])
	default:
		printUsage(os.Stderr)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "nixpp:", err)
		os.Exit(1)
	}
}

func printUsage(output io.Writer) {
	fmt.Fprintln(output, "Usage:")
	fmt.Fprintln(output, "  nixpp fetch --cache URL --store-path /nix/store/HASH-name --destination DIR --public-key NAME:BASE64")
	fmt.Fprintln(output, "  nixpp switch --flake FLAKE[#OUTPUT] --builder SSH_HOST [--public-key NAME:BASE64]")
}

func switchProfile(args []string) (retErr error) {
	flags := flag.NewFlagSet("switch", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	flags.Usage = func() {
		fmt.Fprintln(os.Stderr, "Usage: nixpp switch --flake FLAKE[#OUTPUT] --builder SSH_HOST [--public-key NAME:BASE64]")
		fmt.Fprintln(os.Stderr, "Build a Termux bundle on a Nix host, verify its Nix signature, and activate it as a generation.")
		fmt.Fprintln(os.Stderr, "Set NIXPP_PUBLIC_KEY to avoid repeating the trusted key.")
		flags.PrintDefaults()
	}
	flake := flags.String("flake", "", "Nix flake installable that produces a Termux bundle")
	builder := flags.String("builder", os.Getenv("NIXPP_BUILDER"), "SSH host with Nix and a signing key configured")
	publicKey := flags.String("public-key", os.Getenv("NIXPP_PUBLIC_KEY"), "trusted Nix cache key NAME:BASE64")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if *flake == "" {
		return errors.New("--flake is required")
	}
	if *builder == "" {
		return errors.New("--builder is required")
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments; pass the flake with --flake")
	}
	if len(*flake) > 4096 || strings.ContainsAny(*flake, "\x00\r\n") {
		return errors.New("flake installable is invalid or too long")
	}
	if !validSSHTarget(*builder) {
		return errors.New("builder must be an SSH host or user@host alias without command-line options")
	}
	if *publicKey == "" {
		return errors.New("a trusted signing key is required; pass --public-key or set NIXPP_PUBLIC_KEY")
	}
	if prefix := os.Getenv("PREFIX"); prefix != "/data/data/com.termux/files/usr" {
		return errors.New("switch must run inside the standard Termux app shell")
	}
	if _, err := exec.LookPath("bash"); err != nil {
		return errors.New("Termux bash is required to activate a generation")
	}

	ui := newProgressUI(os.Stderr)
	ui.title()
	var storePath string
	if err := ui.stage("🧱 Build flake on "+*builder, func() error {
		var err error
		storePath, err = remoteBuild(*builder, *flake)
		return err
	}); err != nil {
		return err
	}

	var remoteTemp string
	var metadata narInfo
	defer func() {
		if remoteTemp != "" {
			if err := remoteRun(*builder, "rm -rf -- "+shellQuote(remoteTemp)); err != nil {
				ui.warning(fmt.Sprintf("Could not remove temporary builder output %s: %v", remoteTemp, err))
			}
		}
	}()
	if err := ui.stage("🔏 Sign and inspect the Nix output", func() error {
		var err error
		remoteTemp, err = remoteOutputCache(*builder, storePath)
		if err != nil {
			return err
		}
		storeHash := strings.SplitN(filepath.Base(storePath), "-", 2)[0]
		metadataText, err := remoteOutput(*builder, "cat -- "+shellQuote(filepath.Join(remoteTemp, "cache", storeHash+".narinfo")))
		if err != nil {
			return fmt.Errorf("read builder cache metadata: %w", err)
		}
		metadata, err = parseNarInfo([]byte(metadataText))
		if err != nil {
			return fmt.Errorf("parse builder cache metadata: %w", err)
		}
		if metadata.storePath != storePath {
			return errors.New("builder metadata StorePath does not match the requested flake output")
		}
		if len(metadata.references) != 0 {
			return errors.New("refusing Termux bundle with Nix store references")
		}
		if err := verifySignature(metadata, *publicKey); err != nil {
			return fmt.Errorf("verify builder signature: %w", err)
		}
		return nil
	}); err != nil {
		return err
	}

	var stage string
	var archivePath, digest, bootstrapPath string
	if err := ui.stage("📦 Transfer and verify the bundle", func() error {
		var err error
		stage, err = makeStagingDirectory("nixpp-switch-")
		if err != nil {
			return err
		}
		narPath := filepath.Join(stage, "output.nar")
		if err := remoteNAR(*builder, storePath, narPath, metadata.narSize); err != nil {
			return err
		}
		if err := extractVerifiedNAR(narPath, metadata, filepath.Join(stage, "bundle")); err != nil {
			return err
		}
		archivePath = filepath.Join(stage, "bundle", "environment.tar.gz")
		digest, err = readArchiveDigest(filepath.Join(stage, "bundle", "SHA256SUMS"))
		if err != nil {
			return fmt.Errorf("invalid Termux bundle: %w", err)
		}
		if err := verifyFileSHA256(archivePath, digest); err != nil {
			return fmt.Errorf("verify Termux archive: %w", err)
		}
		bootstrapPath = filepath.Join(stage, "bundle", "bootstrap.sh")
		if info, err := os.Stat(bootstrapPath); err != nil || !info.Mode().IsRegular() {
			return errors.New("Termux bundle is missing a regular bootstrap.sh")
		}
		return nil
	}); err != nil {
		if stage != "" {
			if cleanupErr := os.RemoveAll(stage); cleanupErr != nil {
				return errors.Join(err, fmt.Errorf("remove local staging directory: %w", cleanupErr))
			}
		}
		return err
	}
	defer func() {
		if err := os.RemoveAll(stage); err != nil {
			retErr = errors.Join(retErr, fmt.Errorf("remove local staging directory: %w", err))
		}
	}()

	if err := ui.stage("🚀 Install and health-check the new generation", func() error {
		command := exec.Command("bash", bootstrapPath, "install", archivePath, digest)
		command.Stdin = os.Stdin
		command.Stdout = os.Stdout
		command.Stderr = os.Stderr
		if err := command.Run(); err != nil {
			return fmt.Errorf("activate Termux generation: %w", err)
		}
		return nil
	}); err != nil {
		return err
	}
	return nil
}

func remoteBuild(builder, flake string) (string, error) {
	output, err := remoteOutput(builder, remoteBuildCommand(flake))
	if err != nil {
		return "", fmt.Errorf("build flake on %s: %w", builder, err)
	}
	paths := strings.Fields(output)
	if len(paths) != 1 || !validStorePath(paths[0]) {
		return "", errors.New("flake build must produce exactly one valid /nix/store output path")
	}
	return paths[0], nil
}

func remoteBuildCommand(flake string) string {
	return "nix build --accept-flake-config --no-link --print-out-paths -- " + shellQuote(flake)
}

func remoteOutputCache(builder, storePath string) (string, error) {
	output, err := remoteOutput(builder, "mktemp -d /tmp/nixpp-switch.XXXXXXXX")
	if err != nil {
		return "", fmt.Errorf("create temporary cache on builder: %w", err)
	}
	path := strings.TrimSpace(output)
	if !validRemoteTemp(path) {
		return "", errors.New("builder returned an unsafe temporary directory")
	}
	command := "references=$(nix-store -q --references " + shellQuote(storePath) + ") && " +
		"if [ -n \"$references\" ]; then echo 'Termux output has Nix references' >&2; exit 1; fi && " +
		"mkdir -- " + shellQuote(path+"/cache") + " && " +
		"nix copy --to " + shellQuote("file://"+path+"/cache") + " " + shellQuote(storePath)
	if err := remoteRun(builder, command); err != nil {
		_ = remoteRun(builder, "rm -rf -- "+shellQuote(path))
		return "", fmt.Errorf("sign and export output on builder: %w", err)
	}
	return path, nil
}

func remoteNAR(builder, storePath, destination string, maximum int64) (retErr error) {
	file, err := os.CreateTemp(filepath.Dir(destination), ".nixpp-nar-")
	if err != nil {
		return err
	}
	path := file.Name()
	closed := false
	defer func() {
		if !closed {
			if err := file.Close(); err != nil {
				retErr = errors.Join(retErr, err)
			}
		}
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			retErr = errors.Join(retErr, err)
		}
	}()

	command := exec.Command("ssh", "-T", "--", builder, "nix nar pack "+shellQuote(storePath))
	stdout, err := command.StdoutPipe()
	if err != nil {
		return err
	}
	command.Stderr = os.Stderr
	if err := command.Start(); err != nil {
		return fmt.Errorf("start NAR transfer from %s: %w", builder, err)
	}
	count, copyErr := io.Copy(file, io.LimitReader(stdout, maximum+1))
	if copyErr != nil || count > maximum {
		_ = command.Process.Kill()
		waitErr := command.Wait()
		if copyErr != nil {
			return errors.Join(fmt.Errorf("receive NAR from %s: %w", builder, copyErr), waitErr)
		}
		return errors.Join(errors.New("builder NAR exceeds its signed size limit"), waitErr)
	}
	if err := command.Wait(); err != nil {
		return fmt.Errorf("receive NAR from %s: %w", builder, err)
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	closed = true
	if err := os.Rename(path, destination); err != nil {
		return err
	}
	return nil
}

func validSSHTarget(target string) bool {
	if target == "" || strings.HasPrefix(target, "-") {
		return false
	}
	for _, char := range target {
		if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || strings.ContainsRune("._@-", char)) {
			return false
		}
	}
	return true
}

func validStorePath(path string) bool {
	if !strings.HasPrefix(path, "/nix/store/") || strings.ContainsAny(path, "\x00\r\n") {
		return false
	}
	base := strings.TrimPrefix(path, "/nix/store/")
	hash, name, ok := strings.Cut(base, "-")
	if !ok || len(hash) != 32 || name == "" || strings.Contains(name, "/") {
		return false
	}
	for _, char := range hash {
		if !strings.ContainsRune(nixBase32Alphabet, char) {
			return false
		}
	}
	for _, char := range name {
		if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || strings.ContainsRune("+._?=-", char)) {
			return false
		}
	}
	return true
}

func validRemoteTemp(path string) bool {
	if !strings.HasPrefix(path, "/tmp/nixpp-switch.") || len(path) != len("/tmp/nixpp-switch.")+8 {
		return false
	}
	for _, char := range strings.TrimPrefix(path, "/tmp/nixpp-switch.") {
		if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9') {
			return false
		}
	}
	return true
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func remoteOutput(builder, remoteCommand string) (string, error) {
	command := exec.Command("ssh", "-T", "--", builder, remoteCommand)
	var output strings.Builder
	command.Stdout = &output
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return "", fmt.Errorf("ssh %s: %w", builder, err)
	}
	return output.String(), nil
}

func remoteRun(builder, remoteCommand string) error {
	_, err := remoteOutput(builder, remoteCommand)
	return err
}

func extractVerifiedNAR(path string, metadata narInfo, destination string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	hasher := sha256.New()
	size, hashErr := io.Copy(hasher, io.LimitReader(file, metadata.narSize+1))
	closeErr := file.Close()
	if hashErr != nil {
		return errors.Join(hashErr, closeErr)
	}
	if closeErr != nil {
		return closeErr
	}
	expected, err := decodeNixHash(metadata.narHash)
	if err != nil {
		return err
	}
	if size != metadata.narSize || !equalBytes(hasher.Sum(nil), expected) {
		return errors.New("builder NAR size or hash does not match its signed metadata")
	}
	file, err = os.Open(path)
	if err != nil {
		return err
	}
	extractErr := extractNAR(file, destination)
	return errors.Join(extractErr, file.Close())
}

func readArchiveDigest(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	if len(data) > 4096 {
		return "", errors.New("SHA256SUMS is unexpectedly large")
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 1 {
		return "", errors.New("SHA256SUMS must contain exactly one archive entry")
	}
	fields := strings.Fields(lines[0])
	if len(fields) != 2 || fields[1] != "environment.tar.gz" || len(fields[0]) != sha256.Size*2 {
		return "", errors.New("SHA256SUMS must contain the environment.tar.gz SHA-256")
	}
	for _, char := range fields[0] {
		if !(char >= '0' && char <= '9' || char >= 'a' && char <= 'f') {
			return "", errors.New("SHA256SUMS contains an invalid lowercase SHA-256")
		}
	}
	return fields[0], nil
}

func verifyFileSHA256(path, expected string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	hasher := sha256.New()
	_, hashErr := io.Copy(hasher, file)
	closeErr := file.Close()
	if hashErr != nil {
		return errors.Join(hashErr, closeErr)
	}
	if closeErr != nil {
		return closeErr
	}
	if fmt.Sprintf("%x", hasher.Sum(nil)) != expected {
		return errors.New("SHA-256 mismatch")
	}
	return nil
}

func makeStagingDirectory(prefix string) (string, error) {
	candidates := make([]string, 0, 3)
	if temporary := os.Getenv("TMPDIR"); temporary != "" {
		candidates = append(candidates, temporary)
	}
	if termuxPrefix := os.Getenv("PREFIX"); termuxPrefix != "" {
		candidates = append(candidates, filepath.Join(termuxPrefix, "tmp"))
	}
	candidates = append(candidates, os.TempDir())
	seen := make(map[string]bool, len(candidates))
	var lastErr error
	for _, candidate := range candidates {
		if seen[candidate] {
			continue
		}
		seen[candidate] = true
		info, err := os.Stat(candidate)
		if err != nil {
			lastErr = err
			continue
		}
		if !info.IsDir() {
			lastErr = fmt.Errorf("temporary path is not a directory: %s", candidate)
			continue
		}
		stage, err := os.MkdirTemp(candidate, prefix)
		if err == nil {
			return stage, nil
		}
		lastErr = err
	}
	return "", fmt.Errorf("create private staging directory: %w", lastErr)
}

func fetch(args []string) (retErr error) {
	flags := flag.NewFlagSet("fetch", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	flags.Usage = func() {
		fmt.Fprintln(os.Stderr, "Usage: nixpp fetch --cache URL --store-path /nix/store/HASH-name --destination DIR --public-key NAME:BASE64")
		fmt.Fprintln(os.Stderr, "Fetch one reference-free output from a signed Nix binary cache.")
		fmt.Fprintln(os.Stderr, "Set NIXPP_PUBLIC_KEY to avoid repeating the trusted key.")
		flags.PrintDefaults()
	}
	cache := flags.String("cache", "", "Nix binary cache URL")
	storePath := flags.String("store-path", "", "full Nix store path")
	destination := flags.String("destination", "", "new directory to create from the cache output")
	publicKey := flags.String("public-key", os.Getenv("NIXPP_PUBLIC_KEY"), "trusted Nix cache key NAME:BASE64")
	netrcFile := flags.String("netrc-file", "", "curl netrc file for authenticated cache access")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
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
	cleanup := func() error { return nil }
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
	defer func() {
		if err := cleanup(); err != nil {
			retErr = errors.Join(retErr, fmt.Errorf("remove temporary netrc: %w", err))
		}
	}()
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

func makeNetrc(host string) (string, func() error, error) {
	username, usernameSet := os.LookupEnv("NIXPP_USERNAME")
	password, passwordSet := os.LookupEnv("NIXPP_PASSWORD")
	if !usernameSet && !passwordSet {
		return "", func() error { return nil }, nil
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
		return "", nil, errors.Join(err, file.Close(), os.Remove(path))
	}
	content := fmt.Sprintf("machine %s login %s password %s\n", host, netrcQuote(username), netrcQuote(password))
	if _, err := io.WriteString(file, content); err != nil {
		return "", nil, errors.Join(err, file.Close(), os.Remove(path))
	}
	if err := file.Close(); err != nil {
		return "", nil, errors.Join(err, os.Remove(path))
	}
	return path, func() error { return os.Remove(path) }, nil
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
		return errors.New("narinfo NarHash must use SHA-256")
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

func downloadAndExtract(rawURL, netrcPath string, info narInfo, destination string) (retErr error) {
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
	defer func() {
		if err := os.RemoveAll(stage); err != nil {
			retErr = errors.Join(retErr, fmt.Errorf("remove staging directory: %w", err))
		}
	}()

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
		return errors.Join(err, archive.Close())
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
			return nil, nil, errors.Join(err, file.Close())
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
		if err := file.Close(); err != nil {
			return nil, nil, err
		}
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
				return errors.Join(err, command.Process.Kill(), command.Wait())
			}
			if err := command.Wait(); err != nil {
				return fmt.Errorf("xz decompression failed: %w: %s", err, strings.TrimSpace(stderr.String()))
			}
			return nil
		}, nil
	default:
		return nil, nil, errors.Join(fmt.Errorf("unsupported compression %q", compression), file.Close())
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
		return "", errors.New("nix base32 encoding requires a SHA-256 digest")
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
