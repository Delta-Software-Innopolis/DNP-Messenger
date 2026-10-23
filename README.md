<p align="center">
  <img src="assets/logo.png" alt="OLEG Messenger Logo" width="350">
</p>

# OLEG MESSENGER
**The P2P Decentralized Chat Network**  
Peer-to-peer messanger where multiple servers synchronise messages without central coordinator. Clients can switch between servers seamlessly, ensuring smooth and decentralised experience.

This product was completed as part of a DNP (Distributed and Network Programming) project by students of Innopolis University.

### Stack
- Go + Gin
- Docker
- Flutter
- PostgreSQL
  
### Features
- Decentralised network  
- Message propogation  
- Deduplication  
- Eventual Consistency  
- Partition Tolerance  

## Architecture
The backend consists of 3 independent servers (running as Docker containers) in a bridge network.  
The P2P system uses a full mesh topology.  
Servers communicate with each other using HTTP (Gin framework), whereas clients interact with servers using WebSocket (Flutter).  
Each server ensures validity and actuality of its data in the database by synchronising with other peers.  

### How to start
**Launch the server:**  

```
git clone https://github.com/Delta-Software-Innopolis/DNP-Messenger
cd DNP-Messenger
cp .env.example .env
docker-compose up --build
```  

**Launch the client:**
- Install `OLEG.apk`
- Launch the app on android device
- In settings, specify the link to your server
