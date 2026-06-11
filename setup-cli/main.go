package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"
)

const (
	defaultProject = "v2ray-subscription-manager"
	adminKey       = "admin_auth"
)

type kvNamespace struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type pagesProject struct {
	Name    string `json:"Project Name"`
	Domains string `json:"Project Domains"`
}

func main() {
	var (
		project  = flag.String("project", defaultProject, "Cloudflare Pages project name")
		password = flag.String("password", "", "optional panel password; omit to let /admin ask on first visit")
		reset    = flag.Bool("reset-password", false, "clear stored panel password so /admin asks for a new one")
		list     = flag.Bool("list-pages", false, "list Cloudflare Pages projects and exit")
		deleteP  = flag.String("delete-page", "", "delete a Cloudflare Pages project and exit")
		noDeploy = flag.Bool("no-deploy", false, "prepare resources but skip deployment")
	)
	flag.Parse()

	root, err := findProjectRoot()
	check(err)
	mustChdir(root)
	fmt.Printf("Project root: %s\n", root)

	if *list {
		check(listPages())
		return
	}
	if *deleteP != "" {
		check(run("npx", "wrangler", "pages", "project", "delete", *deleteP, "--yes"))
		return
	}

	check(requireTools())
	check(ensureLogin())
	prodID, previewID, err := ensureKV()
	check(err)
	check(writeWranglerToml(*project, prodID, previewID))
	check(ensurePagesProject(*project))

	if !*noDeploy {
		check(run("npx", "wrangler", "pages", "deploy", "public", "--project-name", *project, "--branch", "main"))
	}

	if *reset || *password == "" {
		check(resetPanelPassword(prodID))
		if *password == "" {
			fmt.Println("Panel password is not set. Open /admin and create it in the browser.")
		}
	} else {
		check(setPanelPassword(*project, *password))
	}

	adminURL := fmt.Sprintf("https://%s.pages.dev/admin/", *project)
	fmt.Printf("\nAdmin panel: %s\n", adminURL)
}

func findProjectRoot() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if exists(filepath.Join(wd, "wrangler.toml")) && exists(filepath.Join(wd, "public")) && exists(filepath.Join(wd, "functions")) {
			return wd, nil
		}
		next := filepath.Dir(wd)
		if next == wd {
			return "", errors.New("could not find project root with wrangler.toml, public, and functions")
		}
		wd = next
	}
}

func requireTools() error {
	for _, tool := range []string{"node", "npm", "npx"} {
		if _, err := exec.LookPath(tool + exeSuffix()); err != nil {
			if _, err2 := exec.LookPath(tool); err2 != nil {
				return fmt.Errorf("%s is required; install Node.js LTS first", tool)
			}
		}
	}
	return run("npm", "install")
}

func ensureLogin() error {
	if err := run("npx", "wrangler", "whoami", "--json"); err == nil {
		fmt.Println("Cloudflare login is active.")
		return nil
	}
	fmt.Println("Opening Cloudflare browser authorization...")
	return run("npx", "wrangler", "login")
}

func ensureKV() (string, string, error) {
	namespaces, err := getKVNamespaces()
	if err != nil {
		return "", "", err
	}
	prodID := namespaces["SUB_KV"]
	previewID := namespaces["SUB_KV_preview"]

	if prodID == "" {
		out, err := output("npx", "wrangler", "kv", "namespace", "create", "SUB_KV")
		if err != nil {
			namespaces, _ = getKVNamespaces()
			prodID = namespaces["SUB_KV"]
			if prodID == "" {
				return "", "", err
			}
		} else {
			prodID = parseID(out, `id\s*=\s*"([^"]+)"`)
		}
	}
	if previewID == "" {
		out, err := output("npx", "wrangler", "kv", "namespace", "create", "SUB_KV", "--preview")
		if err != nil {
			namespaces, _ = getKVNamespaces()
			previewID = namespaces["SUB_KV_preview"]
			if previewID == "" {
				return "", "", err
			}
		} else {
			previewID = parseID(out, `preview_id\s*=\s*"([^"]+)"`)
		}
	}
	if prodID == "" || previewID == "" {
		return "", "", errors.New("could not resolve SUB_KV and SUB_KV_preview namespace IDs")
	}
	fmt.Printf("KV: SUB_KV=%s SUB_KV_preview=%s\n", prodID, previewID)
	return prodID, previewID, nil
}

func getKVNamespaces() (map[string]string, error) {
	out, err := output("npx", "wrangler", "kv", "namespace", "list")
	if err != nil {
		return nil, err
	}
	var list []kvNamespace
	if err := json.Unmarshal([]byte(extractJSONArray(out)), &list); err != nil {
		return nil, err
	}
	m := map[string]string{}
	for _, item := range list {
		m[strings.TrimSpace(item.Title)] = item.ID
	}
	return m, nil
}

func ensurePagesProject(project string) error {
	out, err := output("npx", "wrangler", "pages", "project", "list", "--json")
	if err == nil {
		var projects []pagesProject
		if json.Unmarshal([]byte(extractJSONArray(out)), &projects) == nil {
			for _, p := range projects {
				if p.Name == project {
					fmt.Printf("Pages project exists: %s\n", project)
					return nil
				}
			}
		}
	}
	return run("npx", "wrangler", "pages", "project", "create", project, "--production-branch", "main")
}

func listPages() error {
	out, err := output("npx", "wrangler", "pages", "project", "list", "--json")
	if err != nil {
		return err
	}
	var projects []pagesProject
	if err := json.Unmarshal([]byte(extractJSONArray(out)), &projects); err != nil {
		return err
	}
	for _, p := range projects {
		fmt.Printf("%s\t%s\n", p.Name, p.Domains)
	}
	return nil
}

func resetPanelPassword(namespaceID string) error {
	if namespaceID == "" {
		return errors.New("missing production KV namespace id")
	}
	_ = run("npx", "wrangler", "kv", "key", "delete", adminKey, "--namespace-id", namespaceID, "--remote")
	return nil
}

func setPanelPassword(project, password string) error {
	if strings.TrimSpace(password) == "" {
		return nil
	}
	url := fmt.Sprintf("https://%s.pages.dev/api/admin/login", project)
	deadline := time.Now().Add(90 * time.Second)
	for {
		body := bytes.NewBufferString(fmt.Sprintf(`{"password":%q}`, strings.TrimSpace(password)))
		resp, err := http.Post(url, "application/json", body)
		if err == nil {
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				fmt.Println("Panel password saved in KV.")
				return nil
			}
		}
		if time.Now().After(deadline) {
			if err != nil {
				return err
			}
			return fmt.Errorf("panel password setup failed at %s", url)
		}
		time.Sleep(5 * time.Second)
	}
}

func writeWranglerToml(project, prodID, previewID string) error {
	content := fmt.Sprintf(`name = "%s"
compatibility_date = "2026-06-11"
pages_build_output_dir = "public"

[[kv_namespaces]]
binding = "SUB_KV"
id = "%s"
preview_id = "%s"
`, project, prodID, previewID)
	return os.WriteFile("wrangler.toml", []byte(content), 0644)
}

func run(name string, args ...string) error {
	_, err := output(name, args...)
	return err
}

func output(name string, args ...string) (string, error) {
	fmt.Printf("> %s %s\n", name, strings.Join(args, " "))
	cmd := exec.Command(name, args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	text := stripANSI(buf.String())
	if strings.TrimSpace(text) != "" {
		fmt.Println(strings.TrimSpace(text))
	}
	if err != nil {
		return text, fmt.Errorf("%s %s failed: %w", name, strings.Join(args, " "), err)
	}
	return text, nil
}

func parseID(text, pattern string) string {
	m := regexp.MustCompile(pattern).FindStringSubmatch(text)
	if len(m) > 1 {
		return m[1]
	}
	return ""
}

func extractJSONArray(text string) string {
	start := strings.Index(text, "[")
	end := strings.LastIndex(text, "]")
	if start >= 0 && end >= start {
		return text[start : end+1]
	}
	return "[]"
}

func stripANSI(text string) string {
	return regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`).ReplaceAllString(text, "")
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func exeSuffix() string {
	if runtime.GOOS == "windows" {
		return ".exe"
	}
	return ""
}

func mustChdir(path string) {
	if err := os.Chdir(path); err != nil {
		check(err)
	}
}

func check(err error) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %v\n", err)
		os.Exit(1)
	}
}
