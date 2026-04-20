package app

import (
	"dnp_messenger/internal/config"
	"dnp_messenger/internal/routes"
)

func Run() {
	config.Load()

	router := routes.Setup()
	router.Run()
}