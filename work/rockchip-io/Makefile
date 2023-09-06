all: io

helloworld: io.o
	$(CC) -o io io.o

clean:
	rm -rf *.o
	rm -rf io

install:
	$(INSTALL) -D -m 0755 io $(TARGET_DIR)/usr/bin
