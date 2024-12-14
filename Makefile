NAME = port_forwarder

all: $(NAME)

$(NAME): src/*.zig
	@ zig build
	@ cp ./zig-out/bin/$(NAME) .

release: win
win: src/*.zig
	@ zig build-exe src/main.zig -O ReleaseSmall -fsingle-threaded -fstrip -target x86_64-windows --name $(NAME)

run: $(NAME)
	@ ./$(NAME)
