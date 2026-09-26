package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"testing"
)

func TestNixBase32MatchesNix(t *testing.T) {
	digest := sha256.Sum256([]byte("abc"))
	want := "1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s"
	got, err := nixBase32Encode(digest[:])
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("nixBase32Encode() = %q, want %q", got, want)
	}
	decoded, err := nixBase32Decode(want)
	if err != nil {
		t.Fatal(err)
	}
	if !equalBytes(decoded, digest[:]) {
		t.Fatal("decoded hash did not match input digest")
	}
}

func TestVerifyNixNarInfoSignature(t *testing.T) {
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	info := narInfo{
		storePath:  "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-package",
		narHash:    "sha256:1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s",
		narSize:    42,
		references: []string{},
		signatures: []string{},
	}
	fingerprint := "1;" + info.storePath + ";" + info.narHash + ";42;"
	signature := ed25519.Sign(private, []byte(fingerprint))
	info.signatures = []string{"test:" + base64.StdEncoding.EncodeToString(signature)}
	key := "test:" + base64.StdEncoding.EncodeToString(public)
	if err := verifySignature(info, key); err != nil {
		t.Fatal(err)
	}
	info.narSize++
	if err := verifySignature(info, key); err == nil {
		t.Fatal("signature unexpectedly accepted after signed metadata changed")
	}
}

func TestParseNarInfoRequiresReferenceFieldAndAcceptsEmptyClosure(t *testing.T) {
	data := []byte("StorePath: /nix/store/0123456789abcdfghijklmnpqrsvwxyz-package\n" +
		"URL: nar/test.nar.gz\n" +
		"Compression: gzip\n" +
		"NarHash: sha256:1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s\n" +
		"NarSize: 3\n" +
		"References: \n" +
		"Sig: test:signature\n")
	info, err := parseNarInfo(data)
	if err != nil {
		t.Fatal(err)
	}
	if len(info.references) != 0 {
		t.Fatalf("expected reference-free output, got %v", info.references)
	}
	withoutReferences := bytes.Replace(data, []byte("References: \n"), nil, 1)
	if _, err := parseNarInfo(withoutReferences); err == nil {
		t.Fatal("narinfo without References field was accepted")
	}
}

func TestSafeCacheURLRejectsTraversalAndExternalHosts(t *testing.T) {
	base, err := url.Parse("https://cache.example/private/termux/cache")
	if err != nil {
		t.Fatal(err)
	}
	for _, candidate := range []string{"../outside", "/outside", "https://evil.example/nar", "nar/object?redirect=1"} {
		if _, err := safeCacheURL(base, candidate); err == nil {
			t.Errorf("unsafe cache URL %q was accepted", candidate)
		}
	}
}

func TestValidateNetrcRequiresPrivateRegularFile(t *testing.T) {
	netrc := filepath.Join(t.TempDir(), "netrc")
	if err := os.WriteFile(netrc, []byte("machine cache.example login user password secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := validateNetrc(netrc); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(netrc, 0644); err != nil {
		t.Fatal(err)
	}
	if err := validateNetrc(netrc); err == nil {
		t.Fatal("netrc with group/world permissions was accepted")
	}
	if err := os.Remove(netrc); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(t.TempDir(), "external"), netrc); err != nil {
		t.Fatal(err)
	}
	if err := validateNetrc(netrc); err == nil {
		t.Fatal("symlinked netrc was accepted")
	}
}

func TestExtractNARDirectory(t *testing.T) {
	root := t.TempDir()
	archive := filepath.Join(root, "fixture.nar")
	output := filepath.Join(root, "output")
	file, err := os.Create(archive)
	if err != nil {
		t.Fatal(err)
	}
	writer := narWriter{w: file}
	writer.string("nix-archive-1")
	writer.string("(")
	writer.string("type")
	writer.string("directory")
	writer.string("entry")
	writer.string("(")
	writer.string("name")
	writer.string("bin")
	writer.string("node")
	writer.string("(")
	writer.string("type")
	writer.string("directory")
	writer.string("entry")
	writer.string("(")
	writer.string("name")
	writer.string("tool")
	writer.string("node")
	writer.string("(")
	writer.string("type")
	writer.string("regular")
	writer.string("executable")
	writer.string("")
	writer.string("contents")
	writer.string("hello")
	writer.string(")")
	writer.string(")")
	writer.string(")")
	writer.string(")")
	writer.string(")")
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	file, err = os.Open(archive)
	if err != nil {
		t.Fatal(err)
	}
	if err := extractNAR(file, output); err != nil {
		t.Fatal(err)
	}
	file.Close()
	contents, err := os.ReadFile(filepath.Join(output, "bin", "tool"))
	if err != nil {
		t.Fatal(err)
	}
	if string(contents) != "hello" {
		t.Fatalf("file contents = %q", contents)
	}
	info, err := os.Stat(filepath.Join(output, "bin", "tool"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0755 {
		t.Fatalf("executable mode = %o, want 755", info.Mode().Perm())
	}
}

func TestExtractNARRejectsTraversal(t *testing.T) {
	var archive bytes.Buffer
	writer := narWriter{w: &archive}
	writer.string("nix-archive-1")
	writer.string("(")
	writer.string("type")
	writer.string("directory")
	writer.string("entry")
	writer.string("(")
	writer.string("name")
	writer.string("../escape")
	writer.string("node")
	writer.string("(")
	writer.string("type")
	writer.string("regular")
	writer.string("contents")
	writer.string("no")
	writer.string(")")
	writer.string(")")
	target := filepath.Join(t.TempDir(), "output")
	if err := extractNAR(bytes.NewReader(archive.Bytes()), target); err == nil {
		t.Fatal("traversal entry unexpectedly extracted")
	}
}

type narWriter struct {
	w io.Writer
}

func (writer narWriter) string(value string) {
	var length [8]byte
	binary.LittleEndian.PutUint64(length[:], uint64(len(value)))
	_, _ = writer.w.Write(length[:])
	_, _ = writer.w.Write([]byte(value))
	padding := (8 - len(value)%8) % 8
	_, _ = writer.w.Write(make([]byte, padding))
}
