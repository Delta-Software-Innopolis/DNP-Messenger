package app

import (
	"time"
	"fmt"
	"net/http"
	"log"
	"encoding/json"

	"dnp_messenger/internal/api"
	"dnp_messenger/internal/config"
	"dnp_messenger/internal/database"
	"dnp_messenger/internal/routes"
)

func syncWithPeers() {
	log.Printf("Sync with peers starting")
	since, _ := database.VeryLastMessageTime()
	for _, peer := range config.AppConfig.Servers {
		if peer == config.AppConfig.Self {
			continue
		}

		go func(peer string) {
			log.Printf("Sync with peer %s", peer)
			url := fmt.Sprintf("%s/sync?since=%s", peer, since.Format(time.RFC3339))

			resp, err := http.Get(url)
			if err != nil {
				log.Printf("sync failed with %s: %v", peer, err)
				return
			}
			defer resp.Body.Close()

			var data api.SyncResponse

			if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
				log.Printf("failed to decode sync response: %v", err)
				return
			}

			applySyncData(data)
		}(peer)
	}
}

func applySyncData(data api.SyncResponse) {
	for _, room := range data.Rooms {
		log.Printf("Sync: upserted room %s", room.Id)
		database.UpsertRoom(room)
	}

	for _, member := range data.Members {
		log.Printf("Sync: upserted member %s", member.Alias)
		database.UpsertMember(member)
	}

	for _, msg := range data.Messages {
		log.Printf("Sync: upserted message %s", msg.Text)
		database.UpsertMessage(msg)
	}
}

func Run() {
	config.Load()
	if err := database.Setup(); err != nil {
		panic(err)
	}
	
	log.Printf("? hello")
	router := routes.Setup()
	go syncWithPeers()
	router.Run("0.0.0.0:8080")
}
