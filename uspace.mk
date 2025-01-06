#Check for using system libs
USE_SYS_LIBS := no

#Userspace app makes here
BUILD_DIR := $(CURDIR)/build
DEPSDIR := $(BUILD_DIR)/deps

CC:=gcc
CCLD:=$(CC)
LD:=ld

ifeq ($(USE_SYS_LIBS), no)
	override CFLAGS += -I$(DEPSDIR)/include
	override LDFLAGS += -L$(DEPSDIR)/lib
	REQ = $(LIBNETFILTER_QUEUE) $(LIBMNL) $(LIBCRYPTO)
endif

override CFLAGS += -DPKG_VERSION=\"$(PKG_FULLVERSION)\" -Wall -Wpedantic -Wno-unused-variable -std=gnu99

LIBNFNETLINK_CFLAGS := -I$(DEPSDIR)/include
LIBNFNETLINK_LIBS := -L$(DEPSDIR)/lib
LIBMNL_CFLAGS := -I$(DEPSDIR)/include
LIBMNL_LIBS := -L$(DEPSDIR)/lib

# PREFIX is environment variable, if not set default to /usr/local
ifeq ($(PREFIX),)
	PREFIX := /usr/local
endif

export CC CCLD LD CFLAGS LDFLAGS LIBNFNETLINK_CFLAGS LIBNFNETLINK_LIBS LIBMNL_CFLAGS LIBMNL_LIBS

APP:=$(BUILD_DIR)/dpiDisabler

SRCS := dpiDisabler.c mangle.c args.c utils.c quic.c tls.c getopt.c
OBJS := $(SRCS:%.c=$(BUILD_DIR)/%.o)

LIBNFNETLINK := $(DEPSDIR)/lib/libnfnetlink.la
LIBMNL := $(DEPSDIR)/lib/libmnl.la
LIBNETFILTER_QUEUE := $(DEPSDIR)/lib/libnetfilter_queue.la
#LIBCRYPTO := $(DEPSDIR)/lib64/libcrypto.a

.PHONY: default all dev dev_attrs prepare_dirs
default: all

run_dev: dev
	bash -c "sudo $(APP)"

dev: dev_attrs all

dev_attrs:
	$(eval CFLAGS := $(CFLAGS) -DDEBUG -ggdb -g3)

all: prepare_dirs $(APP)

prepare_dirs:
	mkdir -p $(BUILD_DIR)
	mkdir -p $(DEPSDIR)

$(LIBCRYPTO):
	cd deps/openssl && ./Configure --prefix=$(DEPSDIR) $(if $(CROSS_COMPILE_PLATFORM),--cross-compile-prefix=$(CROSS_COMPILE_PLATFORM)-,) --no-shared
	$(MAKE) -C deps/openssl
	$(MAKE) install_sw -C deps/openssl

$(LIBNFNETLINK):
	cd deps/libnfnetlink && ./autogen.sh && ./configure --prefix=$(DEPSDIR) $(if $(CROSS_COMPILE_PLATFORM),--host=$(CROSS_COMPILE_PLATFORM),) --enable-static --disable-shared
	$(MAKE) -C deps/libnfnetlink
	$(MAKE) install -C deps/libnfnetlink
	
$(LIBMNL):
	cd deps/libmnl && ./autogen.sh && ./configure --prefix=$(DEPSDIR) $(if $(CROSS_COMPILE_PLATFORM),--host=$(CROSS_COMPILE_PLATFORM),) --enable-static --disable-shared
	$(MAKE) -C deps/libmnl
	$(MAKE) install -C deps/libmnl

$(LIBNETFILTER_QUEUE): $(LIBNFNETLINK) $(LIBMNL) 
	cd deps/libnetfilter_queue && ./autogen.sh && ./configure --prefix=$(DEPSDIR) $(if $(CROSS_COMPILE_PLATFORM),--host=$(CROSS_COMPILE_PLATFORM),) --enable-static --disable-shared
	$(MAKE) -C deps/libnetfilter_queue
	$(MAKE) install -C deps/libnetfilter_queue

$(APP): $(OBJS) $(REQ)
	@echo 'CCLD $(APP)'
	$(CCLD) $(OBJS) -o $(APP) $(LDFLAGS) -lmnl -lnetfilter_queue -lpthread

$(BUILD_DIR)/%.o: %.c $(REQ) config.h
	@echo 'CC $@'
	$(CC) -c $(CFLAGS) $(LDFLAGS) $< -o $@

install: all
	install -d $(DESTDIR)$(PREFIX)/bin/
	install -m 755 $(APP) $(DESTDIR)$(PREFIX)/bin/
	install -d $(DESTDIR)$(PREFIX)/lib/systemd/system/
	@cp dpiDisabler.service $(BUILD_DIR)
	@sed -i 's/$$(PREFIX)/$(subst /,\/,$(PREFIX))/g' $(BUILD_DIR)/dpiDisabler.service
	install -m 644 $(BUILD_DIR)/dpiDisabler.service $(DESTDIR)$(PREFIX)/lib/systemd/system/

uninstall:
	rm $(DESTDIR)$(PREFIX)/bin/dpiDisabler
	rm $(DESTDIR)$(PREFIX)/lib/systemd/system/dpiDisabler.service
	-systemctl disable dpiDisabler.service

clean:
	find $(BUILD_DIR) -maxdepth 1 -type f | xargs rm -rf

distclean: clean
	rm -rf $(BUILD_DIR)
ifeq ($(USE_SYS_LIBS), no)
	$(MAKE) distclean -C deps/libnetfilter_queue || true
	$(MAKE) distclean -C deps/libmnl || true
	$(MAKE) distclean -C deps/libnfnetlink || true
	#$(MAKE) distclean -C deps/openssl || true
endif
