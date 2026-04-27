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
	router.GET("/propagate", api.PropagateMessage)

	{
		room := router.Group("/room")

		room.POST("/create", api.CreateRoom)
		room.POST("/join", api.JoinRoom)
		room.POST("/leave", api.LeaveRoom)
		room.POST("/propagate", api.PropagateRoom)
	}

	return router
}
