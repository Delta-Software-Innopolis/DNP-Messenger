package models

type Room struct {
	Id int
	Name string
	LastMsg string
	Members []string
}