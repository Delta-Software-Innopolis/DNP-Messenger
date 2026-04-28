#flowchart TB
    subgraph System["Messenger"]
        direction TB
        
        UC1("Send Message")
        UC2("Join Channel")
        UC3("Create Channel")
        UC4("Leave Channel")
        UC5("View Messages")
    end

    Actor["User"]
    
    Actor --- UC1
    Actor --- UC2
    Actor --- UC3
    Actor --- UC4
    Actor --- UC5 DNP-Messenger
