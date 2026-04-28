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
