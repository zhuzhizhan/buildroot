all: helloworld

helloworld: helloworld.o
	$(CC) -o helloworld helloworld.o

clean:
	rm -rf *.o
	rm -rf helloworld

install:
	$(INSTALL) -D -m 0755 helloworld $(TARGET_DIR)/bin
