Compile-only stand-ins for the few game classes the agent calls (names and signatures only,
no game code). They are used by build.sh to compile the agent and are NOT put in the jar; at
run time the server's own projectzomboid.jar provides the real classes.
