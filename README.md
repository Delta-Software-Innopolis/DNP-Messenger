<p align="center">
  <img src="assets/logo.png" alt="OLEG Messenger Logo" width="350">
</p>

# OLEG MESSENGER
**The P2P Decentralized Chat Network**  
Peer-to-peer messanger where multiple servers synchronise messages without central coordinator. Clients can switch between servers seamlessly, ensuring smooth and decentralised experience.

This product was completed as part of a DNP (Distributed and Network Programming) project by students of Innopolis University.

https://github.com/user-attachments/assets/c63c205c-70cf-4a9e-912c-1c5d0b59d43a

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

<center>
<img width="410" height="410" alt="photo_2026-10-23_14-52-24" src="https://github.com/user-attachments/assets/1062f066-9297-43ca-be3e-74f6fce465af" />

<img width="348" height="225" alt="photo_2026-10-23_14-52-26" src="https://github.com/user-attachments/assets/4c1aebb5-4821-43dd-89a7-c2b57a843183" />

<img width="189" height="253" alt="photo_2026-10-23_14-52-28" src="https://github.com/user-attachments/assets/1952f613-9bf7-44cf-9f3f-46a90648377d" />
</center>
