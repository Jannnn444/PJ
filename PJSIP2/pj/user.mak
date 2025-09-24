//
//  user.mak
//  PJSIP2
//
//  Created by Hualiteq International on 2025/9/23.
//

# Still in pjproject-2.15 directory
cat > user.mak << 'EOF'
export LDFLAGS += -framework Network -framework Security -framework VideoToolbox
EOF
