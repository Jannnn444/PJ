//
//  config_site.h
//  PJSIP2
//
//  Created by Hualiteq International on 2025/9/23.
//

#ifndef __PJ_CONFIG_SITE_H__
#define __PJ_CONFIG_SITE_H__

/* Force endianness for iOS - all iOS devices are little endian */
#undef PJ_IS_LITTLE_ENDIAN
#undef PJ_IS_BIG_ENDIAN
#define PJ_IS_LITTLE_ENDIAN 1
#define PJ_IS_BIG_ENDIAN 0

/* iOS specific configurations */
#define PJ_CONFIG_IPHONE 1

/* Media configurations */
#define PJMEDIA_HAS_VIDEO 1
#define PJMEDIA_HAS_VID_TOOLBOX_CODEC 1

/* SSL configurations */
#define PJ_HAS_SSL_SOCK 1
#define PJ_SSL_SOCK_IMP PJ_SSL_SOCK_IMP_APPLE

/* iOS optimizations */
#define PJ_OS_HAS_CHECK_STACK 0
#define PJSIP_DONT_SWITCH_TO_TCP 1

/* Processor specific - force ARM detection */
#define PJ_M_ARM 1

/* Include the sample config AFTER our definitions */
#include <pj/config_site_sample.h>

#endif /* __PJ_CONFIG_SITE_H__ */
