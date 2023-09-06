################################################################################
#
# helloworld
#
################################################################################

ROCKCHIP_IO_VERSION = 1.0.0
#源码下载方式为本地
ROCKCHIP_IO_SITE_METHOD:=local
#源码路径
ROCKCHIP_IO_SITE = $(CURDIR)/work/rockchip-io
ROCKCHIP_IO_INSTALL_TARGET:=YES



define ROCKCHIP_IO_BUILD_CMDS
	$(MAKE) CC="$(TARGET_CC)" LD="$(TARGET_LD)" -C $(@D) all
endef

define ROCKCHIP_IO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/io $(TARGET_DIR)/usr/bin/
endef

define ROCKCHIP_IO_PERMISSIONS
	/usr/bin/io f 4755 0 0 - - - - -
endef

$(eval $(generic-package))
