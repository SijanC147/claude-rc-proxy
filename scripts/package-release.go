// package-release creates a deterministic release archive from one staged build.
package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

type archiveFile struct {
	name string
	mode int64
}

var archiveFiles = []archiveFile{
	{name: "claude-rc-proxy", mode: 0o755},
	{name: "LICENSE", mode: 0o644},
	{name: "README.md", mode: 0o644},
}

func run(outputPath, stageDir string) error {
	outputDir := filepath.Dir(outputPath)
	temporary, err := os.CreateTemp(outputDir, ".claude-rc-proxy-*.tar.gz")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer temporary.Close()
	completed := false
	defer func() {
		if !completed {
			_ = os.Remove(temporaryPath)
		}
	}()

	gzipWriter, err := gzip.NewWriterLevel(temporary, gzip.BestCompression)
	if err != nil {
		_ = temporary.Close()
		return err
	}
	gzipWriter.Header.ModTime = time.Unix(0, 0).UTC()
	gzipWriter.Header.OS = 255
	tarWriter := tar.NewWriter(gzipWriter)
	epoch := time.Unix(0, 0).UTC()

	for _, file := range archiveFiles {
		path := filepath.Join(stageDir, file.name)
		info, err := os.Stat(path)
		if err != nil {
			return err
		}
		header := &tar.Header{
			Name:     file.name,
			Mode:     file.mode,
			Size:     info.Size(),
			ModTime:  epoch,
			Typeflag: tar.TypeReg,
			Format:   tar.FormatUSTAR,
		}
		if err := tarWriter.WriteHeader(header); err != nil {
			return err
		}
		input, err := os.Open(path)
		if err != nil {
			return err
		}
		_, copyErr := io.Copy(tarWriter, input)
		closeErr := input.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
	}

	if err := tarWriter.Close(); err != nil {
		return err
	}
	if err := gzipWriter.Close(); err != nil {
		return err
	}
	if err := temporary.Sync(); err != nil {
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Chmod(temporaryPath, 0o644); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, outputPath); err != nil {
		return err
	}
	completed = true
	return nil
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: package-release <output.tar.gz> <stage-directory>")
		os.Exit(64)
	}
	if err := run(os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintf(os.Stderr, "package release: %v\n", err)
		os.Exit(1)
	}
}
