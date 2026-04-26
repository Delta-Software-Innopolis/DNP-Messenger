package config

import (
	"os"
	"strconv"
	"log"
)

type Config struct {
	Database struct {
		Host     string
		Port     int
		User     string
		Password string
		Name     string
	}
	Servers []string
	Self string
}

var AppConfig Config

func Load() {
	AppConfig.Database.Host = os.Getenv("DB_HOST")
	AppConfig.Database.User = os.Getenv("DB_USER")
	AppConfig.Database.Password = os.Getenv("DB_PASSWORD")
	AppConfig.Database.Name = os.Getenv("DB_NAME")

	dbport, err := strconv.Atoi(os.Getenv("DB_PORT"))
	AppConfig.Servers = []string{
		"http://backend1:8080",
		"http://backend2:8080",
		"http://backend3:8080",
	}

	AppConfig.Self = os.Getenv("SELF_ADDR")
	if AppConfig.Self == "" {
		panic("SELF_ADDR not set")
	}

	if err != nil {
		panic("Port is invalid")
	}

	log.Printf("my self_addr = %s", AppConfig.Self)

	AppConfig.Database.Port = dbport

}
