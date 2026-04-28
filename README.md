# OLEG MESSENGER
**The P2P Decentralized Chat Network**  
Peer-to-peer messanger where multiple servers synchronise messages without central coordinator. Clients can switch between servers seamlessly, ensuring smooth and decentralised experience.

This product was completed as part of a DNP (Distributed and Network Programming) project by students of Innopolis University.

### Stack
- Go
- Docker
- Flutter
- Gin
  
## Use case diagram
```mermaid
flowchart LR
    subgraph System["Messenger OLEG"]
        Send["Send Message"]
        Join["Join Channel"]
        Create["Create Channel"]
        Leave["Leave Channel"]
        View["View Messages"]
    end

    User(["User"])
    
    User --- Send
    User --- Join
    User --- Create
    User --- Leave
    User --- View
```
### Features
- Decentralised network  
- Message propogation  
- Deduplication  
- Eventual Consistency  
- Partition Tolerance  

## Architecture
```mermaid
flowchart LR
    subgraph Network["Docker Network"]
        Host1["Host 1"]
        Host2["Host 2"]
        Host3["Host 3"]
        
        DB1[("DB1")]
        DB2[("DB2")]
        DB3[("DB3")]
        
        Host1 --- DB1
        Host2 --- DB2
        Host3 --- DB3
        
        Host1 --- Host2
        Host1 --- Host3
        Host2 --- Host3
    end

    User(["User"])
    
    User -.-> Host1
    User -.-> Host2
    User -.-> Host3
```
The backend consists of 3 independent servers (running as Docker containers) in a bridge network.  
The P2P system uses a full mesh topology.  
Servers communicate with each other using HTTP (Gin framework), whereas clients interact with servers using WebSocket (Flutter).  
Each server ensures validity and actuality of its data in the database by synchronising with other peers.  

### How to start
**Prerequisites**
- Docker
- Go


**Launch the server:**  

```
git clone https://github.com/Delta-Software-Innopolis/DNP-Messenger
cd DNP-Messenger
docker-compose up --build
```  

**Launch the client:**
- Install `OLEG.apk`
- Launch the app on android device
- In settings, specify the link to your server
