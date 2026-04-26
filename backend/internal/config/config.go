package config

import (
	"os"
	"strconv"
)

type Config struct {
	Database struct {
		Host     string
		Port     int
		User     string
		Password string
		Name     string
	}
}

var AppConfig Config

func Load() {
	AppConfig.Database.Host = os.Getenv("DB_HOST")
	AppConfig.Database.User = os.Getenv("DB_USER")
	AppConfig.Database.Password = os.Getenv("DB_PASSWORD")
	AppConfig.Database.Name = os.Getenv("DB_NAME")

	dbport, err := strconv.Atoi(os.Getenv("DB_PORT"))

	if err != nil {
		panic("Port is invalid")
	}

	AppConfig.Database.Port = dbport

}
