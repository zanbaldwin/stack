package main

import "log"
import "os"
import "regexp"
import "strings"
import "text/template"

const (
	envTemplate = `{{ .Prefix }}{{ .EnvName }}{{ .Delimiter }}{{ .EnvValue }}{{ .Suffix }}`
)

type ShellConfig struct {
	Prefix    string
	EnvName   string
	Delimiter string
	EnvValue  string
	Suffix    string
}

func getFallbackValues() map[string]string {
	fallbacks := make(map[string]string)
	fallbacks["user"] = "root"
	fallbacks["pass"] = ""
	fallbacks["port"] = "3306"
	return fallbacks
}

func parseDatabaseString(str string) map[string]string {
	r := regexp.MustCompile(`^(?P<driver>[^\:]+)\://(?:(?P<user>[^\:@]+)(?:\:(?P<pass>[^\@]*))?\@)?(?P<host>[^\:@/]+)(?:\:(?P<port>[1-9]\d*))?/(?P<name>[^\?]+)(?:\?(.*))?$`)
	matches := r.FindStringSubmatch(str)
	if matches == nil {
		log.Fatal("Invalid Database String Input")
	}
	fallbacks := getFallbackValues()
	result := make(map[string]string)
	for i, name := range r.SubexpNames() {
		if i != 0 && name != "" {
			result[name] = matches[i]
			if fallback, ok := fallbacks[name]; result[name] == "" && ok {
				result[name] = fallback
			}
		}
	}
	return result
}

func generateShellEnvExportForVars(config *ShellConfig, envVarMap map[string]string) {
	t := template.New("envConfig")
	tmpl, err := t.Parse(envTemplate)
	if err != nil {
		log.Fatal("Could not parse env export template.")
	}
	for key, value := range envVarMap {
		config.EnvName = strings.Join([]string{"DB", strings.ToUpper(key)}, "_")
		config.EnvValue = value
		tmpl.Execute(os.Stdout, config)
	}
}

func main() {
	databaseString := os.Args[1]
	dbvars := parseDatabaseString(databaseString)
	if dbvars["driver"] != "mysql" {
		log.Fatal("Invalid driver; only MySQL is supported.")
	}
	bashConfig := &ShellConfig{
		Prefix:    "export ",
		Delimiter: "=\"",
		Suffix:    "\"\n",
	}
	generateShellEnvExportForVars(bashConfig, dbvars)
}
