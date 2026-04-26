package models

type Room struct {
	Id        string   `json:"id"`
	Name      string   `json:"name"`
	LastMsg   string   `json:"last_msg"`
	LastMsgID int      `json:"last_msg_id"`
	Members   []string `json:"members"`
	Invite    string   `json:"invite"`
}
