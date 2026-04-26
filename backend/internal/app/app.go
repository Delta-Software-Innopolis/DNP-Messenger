package app

import (
	"dnp_messenger/internal/config"
	"dnp_messenger/internal/database"
	"dnp_messenger/internal/routes"
)

func Run() {
	config.Load()
	if err := database.Setup(); err != nil {
		panic(err)
	}

	router := routes.Setup()
	router.Run("0.0.0.0:8080")
}
