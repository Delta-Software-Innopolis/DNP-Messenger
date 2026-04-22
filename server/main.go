package main 

import (
	"fmt"
	"net/http"
	"database/sql"
	"log"
	"os"

	_ "github.com/lib/pq"
)

func main() {
	user := os.Getenv("DB_USER")
	pass := os.Getenv("DB_PASS")
	dbn := os.Getenv("DB_NAME")

	connStr := fmt.Sprintf(
	    "postgres://%s:%s@db1:5432/%s?sslmode=disable",
	    user, pass, dbn,
	)
	db, err := sql.Open("postgres", connStr)

	if err != nil {
		log.Fatal(err)
	}
	err = db.Ping()
	if err != nil {
		log.Fatal("DB not reachable:", err)
	}
	fmt.Println("Connected to DB!")

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello World!")
	})

	http.ListenAndServe(":8080", nil)
}
