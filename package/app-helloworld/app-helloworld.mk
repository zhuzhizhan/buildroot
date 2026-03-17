################################################################################
#
# helloworld
#
################################################################################

APP_HELLOWORLD_VERSION = 1.0.0
APP_HELLOWORLD_SITE_METHOD:=local
APP_HELLOWORLD_SITE = $(CURDIR)/work/helloworld
APP_HELLOWORLD_INSTALL_TARGET:=YES



define APP_HELLOWORLD_BUILD_CMDS
    $(MAKE) CC="$(TARGET_CC)" LD="$(TARGET_LD)" -C $(@D) all
endef

define APP_HELLOWORLD_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/helloworld $(TARGET_DIR)/bin
endef

define APP_HELLOWORLD_PERMISSIONS
    /bin/helloworld f 4755 0 0 - - - - -
endef

$(eval $(generic-package))

