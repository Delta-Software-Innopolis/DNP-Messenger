package database

import (
	"context"
	"fmt"
	"time"

	"dnp_messenger/internal/config"
	"dnp_messenger/internal/models"
	"dnp_messenger/pkg/utils"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

var DB *pgxpool.Pool

func Setup() error {
	connString := fmt.Sprintf(
		"postgres://%s:%s@%s:%d/%s",
		config.AppConfig.Database.User,
		config.AppConfig.Database.Password,
		config.AppConfig.Database.Host,
		config.AppConfig.Database.Port,
		config.AppConfig.Database.Name,
	)

	ctx := context.Background()
	var pool *pgxpool.Pool
	var err error

	for attempt := 1; attempt <= 10; attempt++ {
		pool, err = pgxpool.New(ctx, connString)
		if err == nil {
			if err = pool.Ping(ctx); err == nil {
				break
			}
			pool.Close()
		}

		if attempt == 10 {
			return fmt.Errorf("Unable to connect to database after %d attempts: %w", attempt, err)
		}

		time.Sleep(2 * time.Second)
	}

	DB = pool

	if err := createTables(ctx); err != nil {
		return fmt.Errorf("Unable to create tables: %w", err)
	}

	return nil
}

func createTables(ctx context.Context) error {
	if _, err := DB.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS rooms (
			id UUID PRIMARY KEY,
			name VARCHAR(100),
			invite_code VARCHAR(10),
			timestamp TIMESTAMP DEFAULT now()
		)
	`); err != nil {
		return err
	}

	if _, err := DB.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS members (
			room_id UUID,
			alias VARCHAR(20),
			timestamp TIMESTAMP DEFAULT now(),
			PRIMARY KEY(room_id, alias)
		)
	`); err != nil {
		return err
	}

	if _, err := DB.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS message (
			id UUID PRIMARY KEY,
			type INT,
			text TEXT,
			sender VARCHAR(20),
			timestamp TIMESTAMP,
			room_id UUID
		)
	`); err != nil {
		return err
	}

	return nil
}

func SaveMessage(msg *models.Message) error {
	ctx := context.Background()

	if msg.Id == "" {
		msg.Id = uuid.NewString()
	}

	_, err := DB.Exec(ctx, `
		INSERT INTO message (id, type, text, sender, timestamp, room_id)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT DO NOTHING
	`, msg.Id, msg.Type, msg.Text, msg.Sender, msg.Timestamp, msg.RoomId)

	if err != nil {
		return fmt.Errorf("unable to save message: %w", err)
	}

	return nil
}

func GetMessage(id string) (*models.Message, error) {
	ctx := context.Background()

	var msg models.Message

	err := DB.QueryRow(ctx, `
		SELECT id, type, text, sender, timestamp, room_id
		FROM message
		WHERE id = $1
	`, id).Scan(
		&msg.Id,
		&msg.Type,
		&msg.Text,
		&msg.Sender,
		&msg.Timestamp,
		&msg.RoomId,
	)

	if err != nil {
		return nil, fmt.Errorf("unable to get message: %w", err)
	}

	return &msg, nil
}

func GetMessagesBefore(room string, count int, before string) ([]models.Message, error) {
	ctx := context.Background()

	msg, err := GetMessage(before)
	if err != nil {
		return nil, err
	}
	if msg == nil {
		return nil, fmt.Errorf("message not found")
	}

	rows, err := DB.Query(ctx, `
		SELECT id, type, text, sender, timestamp, room_id
		FROM message
		WHERE room_id = $1 AND timestamp <= $2
		ORDER BY timestamp DESC, id DESC
		LIMIT $3
	`, room, msg.Timestamp, count)

	if err != nil {
		return nil, fmt.Errorf("Unable to query messages: %w", err)
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var m models.Message
		if err := rows.Scan(&m.Id, &m.Type, &m.Text, &m.Sender, &m.Timestamp, &m.RoomId); err != nil {
			return nil, fmt.Errorf("Unable to scan message: %w", err)
		}
		messages = append(messages, m)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("Error iterating messages: %w", err)
	}

	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	return messages, nil
}

func GetMessagesAfter(room string, after string) ([]models.Message, error) {
	ctx := context.Background()

	msg, err := GetMessage(after)
	if err != nil {
		return nil, err
	}
	if msg == nil {
		return nil, fmt.Errorf("message not found")
	}

	rows, err := DB.Query(ctx, `
		SELECT id, type, text, sender, timestamp, room_id
		FROM message
		WHERE room_id = $1 AND timestamp >= $2
		ORDER BY timestamp ASC, id ASC
	`, room, msg.Timestamp)

	if err != nil {
		return nil, fmt.Errorf("unable to query messages: %w", err)
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var m models.Message
		if err := rows.Scan(&m.Id, &m.Type, &m.Text, &m.Sender, &m.Timestamp, &m.RoomId); err != nil {
			return nil, fmt.Errorf("unable to scan message: %w", err)
		}
		messages = append(messages, m)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating messages: %w", err)
	}

	return messages, nil
}

func GetLastMessage(room string) (*models.Message, error) {
	ctx := context.Background()

	var msg models.Message
	err := DB.QueryRow(ctx, `
		SELECT id, type, text, sender, timestamp, room_id
		FROM message
		WHERE room_id = $1
		ORDER BY timestamp DESC, id DESC
		LIMIT 1
	`, room).Scan(&msg.Id, &msg.Type, &msg.Text, &msg.Sender, &msg.Timestamp, &msg.RoomId)

	if err != nil {
		return nil, fmt.Errorf("Unable to get last message: %w", err)
	}

	return &msg, nil
}

func VeryLastMessageTime() (time.Time, error) {
	ctx := context.Background()
	var t time.Time

	err := DB.QueryRow(ctx, `
		SELECT timestamp
		FROM message
		ORDER BY timestamp DESC, id DESC
		LIMIT 1
	`).Scan(&t)

	if err != nil {
		return time.Time{}, fmt.Errorf("Unable to get very last message: %w", err)
	}

	return t, nil
}

func CreateRoom(name string) (*models.Room, error) {
	roomID := uuid.NewString()
	return CreateRoomWithID(roomID, name)
}

func CreateRoomWithID(id, name string) (*models.Room, error) {
	ctx := context.Background()

	if DB == nil {
		return nil, fmt.Errorf("Database connection not initialized")
	}

	_, err := DB.Exec(ctx, `
		INSERT INTO rooms (id, name, invite_code)
		VALUES ($1, $2, '')
		ON CONFLICT DO NOTHING
	`, id, name)

	if err != nil {
		return nil, fmt.Errorf("Unable to create room with ID: %w", err)
	}

	inviteCode := utils.GenerateInviteCode(name, id)

	_, err = DB.Exec(ctx, `
		UPDATE rooms
		SET invite_code = $1,
		    timestamp = now()
		WHERE id = $2
	`, inviteCode, id)

	if err != nil {
		return nil, fmt.Errorf("Unable to update invite code: %w", err)
	}

	return &models.Room{
		Id:        id,
		Name:      name,
		LastMsg:   "",
		LastMsgID: "",
		Members:   []string{},
		Invite:    inviteCode,
	}, nil
}

func AddMember(roomID string, alias string) error {
	ctx := context.Background()

	_, err := DB.Exec(ctx, `
		INSERT INTO members (room_id, alias, timestamp)
		VALUES ($1, $2, now())
		ON CONFLICT DO NOTHING
	`, roomID, alias)

	if err != nil {
		return fmt.Errorf("Unable to add member: %w", err)
	}

	return nil
}

func GetRoom(roomID string) (*models.Room, error) {
	ctx := context.Background()

	var room models.Room

	err := DB.QueryRow(ctx, `
		SELECT id, name, invite_code
		FROM rooms
		WHERE id = $1
	`, roomID).Scan(&room.Id, &room.Name, &room.Invite)

	if err != nil {
		return nil, fmt.Errorf("Unable to get room: %w", err)
	}

	lastMsg, err := GetLastMessage(roomID)
	if err == nil && lastMsg != nil {
		room.LastMsg = lastMsg.Text
		room.LastMsgID = lastMsg.Id
	}

	rows, err := DB.Query(ctx, `
		SELECT alias
		FROM members
		WHERE room_id = $1
	`, roomID)

	if err != nil {
		return nil, fmt.Errorf("Unable to get members: %w", err)
	}
	defer rows.Close()

	room.Members = []string{}

	for rows.Next() {
		var alias string
		if err := rows.Scan(&alias); err != nil {
			return nil, fmt.Errorf("Unable to scan member: %w", err)
		}
		room.Members = append(room.Members, alias)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("Error iterating members: %w", err)
	}

	return &room, nil
}

func GetAllMessagesAfter(t time.Time) ([]models.Message, error) {
	ctx := context.Background()

	rows, err := DB.Query(ctx, `
		SELECT id, type, text, sender, timestamp, room_id
		FROM message
		WHERE timestamp > $1
		ORDER BY timestamp ASC, id ASC
	`, t)

	if err != nil {
		return nil, fmt.Errorf("unable to query messages: %w", err)
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var m models.Message
		if err := rows.Scan(&m.Id, &m.Type, &m.Text, &m.Sender, &m.Timestamp, &m.RoomId); err != nil {
			return nil, fmt.Errorf("unable to scan message: %w", err)
		}
		messages = append(messages, m)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating messages: %w", err)
	}

	return messages, nil
}

func GetAllRoomsAfter(t time.Time) ([]models.Room, error) {
	ctx := context.Background()

	rows, err := DB.Query(ctx, `
		SELECT id, name, invite_code
		FROM rooms
		WHERE timestamp > $1
		ORDER BY timestamp ASC, id ASC
	`, t)

	if err != nil {
		return nil, fmt.Errorf("unable to query rooms: %w", err)
	}
	defer rows.Close()

	var rooms []models.Room
	for rows.Next() {
		var room models.Room
		if err := rows.Scan(&room.Id, &room.Name, &room.Invite); err != nil {
			return nil, fmt.Errorf("unable to scan room: %w", err)
		}

		lastMsg, err := GetLastMessage(room.Id)
		if err == nil && lastMsg != nil {
			room.LastMsg = lastMsg.Text
			room.LastMsgID = lastMsg.Id
		}

		room.Members, err = getRoomMembers(ctx, room.Id)
		if err != nil {
			return nil, err
		}

		rooms = append(rooms, room)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating rooms: %w", err)
	}

	return rooms, nil
}

func GetAllMembersAfter(t time.Time) ([]models.Member, error) {
	ctx := context.Background()

	rows, err := DB.Query(ctx, `
		SELECT room_id, alias
		FROM members
		WHERE timestamp > $1
		ORDER BY timestamp ASC, room_id ASC
	`, t)

	if err != nil {
		return nil, fmt.Errorf("unable to query members: %w", err)
	}
	defer rows.Close()

	var members []models.Member
	for rows.Next() {
		var m models.Member
		if err := rows.Scan(&m.RoomID, &m.Alias); err != nil {
			return nil, fmt.Errorf("unable to scan member: %w", err)
		}
		members = append(members, m)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating members: %w", err)
	}

	return members, nil
}

func getRoomMembers(ctx context.Context, roomID string) ([]string, error) {
	rows, err := DB.Query(ctx, `
		SELECT alias
		FROM members
		WHERE room_id = $1
	`, roomID)
	if err != nil {
		return nil, fmt.Errorf("Unable to get members: %w", err)
	}
	defer rows.Close()

	members := make([]string, 0)
	for rows.Next() {
		var alias string
		if err := rows.Scan(&alias); err != nil {
			return nil, fmt.Errorf("Unable to scan member: %w", err)
		}
		members = append(members, alias)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("Error iterating members: %w", err)
	}

	return members, nil
}

func GetRoomsOf(alias string) ([]models.Room, error) {
	if DB == nil {
		return nil, fmt.Errorf("Database connection not initialized")
	}

	ctx := context.Background()

	rows, err := DB.Query(ctx, `
		SELECT r.id, r.name, r.invite_code
		FROM rooms r
		JOIN members m ON m.room_id = r.id
		WHERE m.alias = $1
	`, alias)
	if err != nil {
		return nil, fmt.Errorf("unable to query rooms: %w", err)
	}
	defer rows.Close()

	var rooms []models.Room
	for rows.Next() {
		var room models.Room
		if err := rows.Scan(&room.Id, &room.Name, &room.Invite); err != nil {
			return nil, fmt.Errorf("unable to scan room: %w", err)
		}

		lastMsg, err := GetLastMessage(room.Id)
		if err == nil && lastMsg != nil {
			room.LastMsg = lastMsg.Text
			room.LastMsgID = lastMsg.Id
		}

		room.Members, err = getRoomMembers(ctx, room.Id)
		if err != nil {
			return nil, err
		}

		rooms = append(rooms, room)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating rooms: %w", err)
	}

	return rooms, nil
}

func GetRoomByInvite(inviteCode string) (*models.Room, error) {
	ctx := context.Background()

	var room models.Room
	err := DB.QueryRow(ctx, `
		SELECT id, name, invite_code
		FROM rooms
		WHERE invite_code = $1
	`, inviteCode).Scan(&room.Id, &room.Name, &room.Invite)

	if err != nil {
		return nil, fmt.Errorf("unable to get room: %w", err)
	}

	lastMsg, err := GetLastMessage(room.Id)
	if err == nil && lastMsg != nil {
		room.LastMsg = lastMsg.Text
		room.LastMsgID = lastMsg.Id
	}

	room.Members, err = getRoomMembers(ctx, room.Id)
	if err != nil {
		return nil, err
	}

	return &room, nil
}

func IsMemberInRoom(roomID string, alias string) (bool, error) {
	ctx := context.Background()

	var exists bool
	err := DB.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM members
			WHERE room_id = $1 AND alias = $2
		)
	`, roomID, alias).Scan(&exists)

	if err != nil {
		return false, fmt.Errorf("unable to check membership: %w", err)
	}

	return exists, nil
}

func RemoveMember(roomID string, alias string) error {
	ctx := context.Background()

	_, err := DB.Exec(ctx, `
		DELETE FROM members
		WHERE room_id = $1 AND alias = $2
	`, roomID, alias)

	if err != nil {
		return fmt.Errorf("Unable to remove member: %w", err)
	}

	return nil
}

func DeleteRoom(roomID string) error {
	ctx := context.Background()

	_, err := DB.Exec(ctx, `
		DELETE FROM message
		WHERE room_id = $1
	`, roomID)
	if err != nil {
		return fmt.Errorf("Unable to delete messages: %w", err)
	}

	_, err = DB.Exec(ctx, `
		DELETE FROM members
		WHERE room_id = $1
	`, roomID)
	if err != nil {
		return fmt.Errorf("Unable to delete members: %w", err)
	}

	_, err = DB.Exec(ctx, `
		DELETE FROM rooms
		WHERE id = $1
	`, roomID)
	if err != nil {
		return fmt.Errorf("Unable to delete room: %w", err)
	}

	return nil
}

func GetMemberCount(roomID string) (int, error) {
	ctx := context.Background()

	var count int
	err := DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM members
		WHERE room_id = $1
	`, roomID).Scan(&count)

	if err != nil {
		return 0, fmt.Errorf("Unable to get member count: %w", err)
	}

	return count, nil
}

func UpsertRoom(room models.Room) error {
	ctx := context.Background()

	_, err := DB.Exec(ctx, `
		INSERT INTO rooms (id, name, invite_code, timestamp)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT DO NOTHING
	`, room.Id, room.Name, room.Invite, room.Timestamp)

	if err != nil {
		return fmt.Errorf("unable to upsert room: %w", err)
	}

	return nil
}

func UpsertMember(member models.Member) error {
	ctx := context.Background()

	_, err := DB.Exec(ctx, `
		INSERT INTO members (room_id, alias, timestamp)
		VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING
	`, member.RoomID, member.Alias, member.Timestamp)

	if err != nil {
		return fmt.Errorf("unable to upsert member: %w", err)
	}

	return nil
}

func UpsertMessage(message models.Message) error {
	ctx := context.Background()

	_, err := DB.Exec(ctx, `
		INSERT INTO message (id, type, text, sender, timestamp, room_id)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT DO NOTHING
	`, message.Id, message.Type, message.Text, message.Sender, message.Timestamp, message.RoomId)

	if err != nil {
		return fmt.Errorf("unable to upsert member: %w", err)
	}

	return nil
}
