package routes

import (
	"dnp_messenger/internal/api"

	"github.com/gin-gonic/gin"
)

func Setup() *gin.Engine {
	router := gin.Default()
	router.SetTrustedProxies([]string{"127.0.0.1"})

	router.GET("/ping/", api.Pong)

	router.GET("/rooms", api.GetRooms)
	router.GET("/ws", api.Websocket)

	{
		room := router.Group("/room")

		room.POST("/create", api.CreateRoom)
		room.POST("/join", api.JoinRoom)
		room.POST("/leave", api.LeaveRoom)

	}

	return router
}
