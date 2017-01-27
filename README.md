# Active peer

This is a little script to connect to applications listening on a given port behind firewalls, routers, etc.

## How it works

You will need a server with a public internet address (can be your own machine - let's call it the source machine).
The use cases are similar to something like Logmein Hamachi: You have an application listening behind a router that you want to connect to, and you have access to this machine (let's call it the target machine).
You run this script in the target and it basically will work by connecting to the source machine from the target, opening another client connection to the application running in the target and then just piping data from one connection to the other.
You then run the same script in the source that opens two listening sockets: one for the remote script, and another to whatever connects to it. So in the target side you have two clients, and in the source side, two servers.


## Usage

In the target machine, you set it up so it tries to connect (active mode) to the source machine, and to the application (assumed to be running on localhost by default):

```
./activePeer.rb ACTIVE -ar --inPort 20002 --inAddr x.x.x.x --outPort 14123 
```

In the source machine, you start two listening sockets (passive mode):

```
./activePeer.rb PASSIVE -r --inPort 15002 --outPort 20002 --outAddr x.x.x.x
```

The 'in' and 'out' addresses/ports refers to the remote machine and the local application, and can be used interchangeably, as the script just pipes data from one connection to another.


## Todo

* Write this readme in a way that is understandable by not just me
* Use better analogy to 'in' and 'out' connections
