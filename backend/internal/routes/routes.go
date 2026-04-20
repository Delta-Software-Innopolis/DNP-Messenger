package routes

import (
	"dnp_messenger/internal/api"

	"github.com/gin-gonic/gin"
)

func Setup() *gin.Engine {
	router := gin.Default()
	
	router.GET("/ping/", api.Pong)

	return router
}