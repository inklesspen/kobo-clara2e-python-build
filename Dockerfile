FROM --platform=linux/arm64 debian:bookworm as setup-stage

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -qqy build-essential gdb lcov pkg-config \
    libbz2-dev libffi-dev libgdbm-dev libgdbm-compat-dev liblzma-dev bison \
    libncurses5-dev libreadline6-dev libsqlite3-dev libssl-dev \
    lzma lzma-dev tk-dev uuid-dev zlib1g-dev patchelf libzstd-dev \
    file ninja-build git opendoas python3 python3-pip python3-packaging \
    curl wget man-db less nano qemu-user-static && rm -rf /var/lib/apt/lists

RUN useradd -s /bin/bash -m builder

RUN echo "permit nopass builder as root" > /etc/doas.conf

USER builder
WORKDIR /home/builder

RUN mkdir -p /home/builder/tc

COPY --chown=builder:builder arm64-arm-kobo-linux-gnueabihf.tar.xz .
RUN tar xf arm64-arm-kobo-linux-gnueabihf.tar.xz -C tc && rm arm64-arm-kobo-linux-gnueabihf.tar.xz

COPY --chown=builder:builder cross-arm-kobo.txt /home/builder/tc/
COPY --chown=builder:builder compile-envs /home/builder/tc/

FROM setup-stage as build-stage

# ADD --chown=builder:builder https://infraroot.at/pub/squashfs/squashfs-tools-ng-1.3.1.tar.xz .
# RUN tar xf squashfs-tools-ng-1.3.1.tar.xz && rm squashfs-tools-ng-1.3.1.tar.xz
# RUN cd squashfs-tools-ng-1.3.1 && ./configure --prefix=/usr && make && doas make install-strip && cd .. && rm -rf squashfs-tools-ng-1.3.1

# Build Python for host (needed for cross-compile)

ADD --chown=builder:builder https://www.python.org/ftp/python/3.12.5/Python-3.12.5.tar.xz .
RUN echo "fa8a2e12c5e620b09f53e65bcd87550d2e5a1e2e04bf8ba991dcc55113876397  Python-3.12.5.tar.xz" | shasum -a 256 --check -

RUN tar xf Python-3.12.5.tar.xz && rm Python-3.12.5.tar.xz

RUN cd Python-3.12.5 && \
    mkdir -p build/host && \
    cd build/host && \
    ../../configure --prefix=/home/builder/tc/python3.12 && make -j$(nproc) && make install

RUN /home/builder/tc/python3.12/bin/pip3.12 install --upgrade pip && \
    /home/builder/tc/python3.12/bin/pip3.12 install meson packaging crossenv python-magic pyelftools

ENV PATH="/home/builder/tc/arm-kobo-linux-gnueabihf/bin:/home/builder/tc/python3.12/bin:${PATH}"
ENV INSTALL_PREFIX=/opt/tabula
ENV CROSS_TRIPLET=arm-kobo-linux-gnueabihf
ENV SYSROOT_DIR=/home/builder/tc/${CROSS_TRIPLET}/${CROSS_TRIPLET}/sysroot

# ENV ARCH_FLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard -mthumb"
# ENV CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} -pipe -fomit-frame-pointer -frename-registers -fweb"
# ENV CXXFLAGS="${CFLAGS}"
# ENV LDFLAGS="-Wl,-O1 -Wl,--as-needed"

ENV CT_XLDD_ROOT=${SYSROOT_DIR}
ENV QEMU_LD_PREFIX=${SYSROOT_DIR}
ENV QEMU_SET_ENV="LD_LIBRARY_PATH=${INSTALL_PREFIX}/lib"

# ENV CC=${CROSS_TRIPLET}-gcc
# ENV CXX=${CROSS_TRIPLET}-g++
# ENV STRIP=${CROSS_TRIPLET}-strip
# ENV AR=${CROSS_TRIPLET}-gcc-ar
# ENV RANLIB=${CROSS_TRIPLET}-gcc-ranlib

ENV PKG_CONFIG=pkg-config
ENV PKG_CONFIG_PATH=${SYSROOT_DIR}${INSTALL_PREFIX}/lib/pkgconfig
ENV PKG_CONFIG_LIBDIR=${SYSROOT_DIR}${INSTALL_PREFIX}/lib/pkgconfig:${SYSROOT_DIR}/usr/lib/pkgconfig:${SYSROOT_DIR}/usr/share/pkgconfig
ENV PKG_CONFIG_SYSROOT_DIR=${SYSROOT_DIR}

# ADD --chown=builder:builder https://mirrors.kernel.org/gnu/ncurses/ncurses-6.5.tar.gz .
# RUN tar xf ncurses-6.5.tar.gz && rm ncurses-6.5.tar.gz
# RUN . tc/compile-envs && cd ncurses-6.5 && ./configure --build=aarch64-linux-gnu --host=${CROSS_TRIPLET}  --prefix=${INSTALL_PREFIX} \
#     --disable-widec --enable-pc-files --with-shared --with-pkg-config-libdir=${INSTALL_PREFIX}/lib/pkgconfig && \
#     make && make install DESTDIR=${SYSROOT_DIR}
    #  && cd .. && rm -rf ncurses-6.5

# remove all traces of the previous ncurses
# RUN cd tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/usr/include/ && \
#     rm curses.h ncurses.h ncurses_dll.h eti.h form.h menu.h panel.h term.h term_entry.h termcap.h unctrl.h && \
#     cd ../lib && rm libform* libmenu* libncurses* libpanel* terminfo && cd ../share && rm -r terminfo

# ADD --chown=builder:builder https://mirrors.kernel.org/gnu/readline/readline-8.2.tar.gz .
# RUN tar xf readline-8.2.tar.gz && rm readline-8.2.tar.gz
# RUN . tc/compile-envs && cd readline-8.2 && ./configure --build=aarch64-linux-gnu --host=${CROSS_TRIPLET}  --prefix=${INSTALL_PREFIX} \
#    --with-curses --with-shared-termcap-library \
#    LDFLAGS="${LDFLAGS} -L${SYSROOT_DIR}${INSTALL_PREFIX}/lib" \
#    CPPFLAGS="-I${SYSROOT_DIR}${INSTALL_PREFIX}/include" \
#    && make && make install DESTDIR=${SYSROOT_DIR}
    # && cd .. && rm -rf readline-8.2


ADD --chown=builder:builder https://mirrors.kernel.org/gnu/readline/readline-7.0.tar.gz .
RUN tar xf readline-7.0.tar.gz && rm readline-7.0.tar.gz
RUN . tc/compile-envs && cd readline-7.0 && ./configure --build=aarch64-linux-gnu --host=${CROSS_TRIPLET}  --prefix="" && \
    make && make install DESTDIR=${SYSROOT_DIR} && cd .. && rm -rf readline-7.0
# Readline doesn't provide a pkgconfig file at 7.0, so we provide our own
COPY --chown=builder:builder readline.pc ./tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/usr/lib/pkgconfig/


# apparently editline is not fully compatible.
# ADD --chown=builder:builder https://thrysoee.dk/editline/libedit-20240517-3.1.tar.gz .
# RUN tar xf libedit-20240517-3.1.tar.gz && rm libedit-20240517-3.1.tar.gz
# RUN . tc/compile-envs && cd libedit-20240517-3.1 && \
#     ./configure --build=aarch64-linux-gnu --host=${CROSS_TRIPLET}  --prefix="${INSTALL_PREFIX}" --with-gnu-ld --disable-examples && \
#     make && DESTDIR=${SYSROOT_DIR} make install && cd .. && rm -rf libedit-20240517-3.1

COPY --chown=builder:builder tabuladeps tabuladeps

RUN cd tabuladeps && \
    meson setup --cross-file /home/builder/tc/cross-arm-kobo.txt --prefix=${INSTALL_PREFIX} -Dbuildtype=debugoptimized -Dstage=one stage-one && \
    meson compile -C stage-one && \
    DESTDIR=${SYSROOT_DIR} meson install -C stage-one && rm -rf stage-one

RUN cd tabuladeps && \
    meson setup --cross-file /home/builder/tc/cross-arm-kobo.txt --prefix=${INSTALL_PREFIX} -Dbuildtype=debugoptimized -Dstage=two stage-two && \
    meson compile -C stage-two && \
    DESTDIR=${SYSROOT_DIR} meson install -C stage-two && rm -rf stage-two

RUN cd tabuladeps && \
    meson setup --cross-file /home/builder/tc/cross-arm-kobo.txt --prefix=${INSTALL_PREFIX} -Dbuildtype=debugoptimized -Dstage=three stage-three && \
    meson compile -C stage-three && \
    DESTDIR=${SYSROOT_DIR} meson install -C stage-three && cd .. && rm -rf tabuladeps

RUN git clone -b v1.25.0 https://github.com/NiLuJe/FBInk.git && cd FBInk && git submodule init && git submodule update
COPY --chown=builder:builder fbink FBInk/

RUN cd FBInk && meson setup --cross-file /home/builder/tc/cross-arm-kobo.txt --prefix=${INSTALL_PREFIX} -Ddefault_library=both \
                            -Ddevice=kobo -Dextra_fonts=disabled -Dopentype=disabled -Dbutton_scan=disabled builddir && \
                meson compile -C builddir && \
                DESTDIR=${SYSROOT_DIR} meson install -C builddir && cd .. && rm -rf FBInk

# can't seem to get openssl to build using the meson setup. oh well.
ADD --chown=builder:builder https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1u/openssl-1.1.1u.tar.gz .
RUN tar xf openssl-1.1.1u.tar.gz && rm openssl-1.1.1u.tar.gz

RUN . tc/compile-envs && cd openssl-1.1.1u && \
    ./Configure linux-generic32 \
        --prefix=${INSTALL_PREFIX} \
        --openssldir=${INSTALL_PREFIX} \
        -shared -no-ssl2 -no-ssl3 -no-weak-ssl-ciphers \
        -DOPENSSL_USE_IPV6=0 \
        -DOPENSSL_TLS_SECURITY_LEVEL=2 && \
    make -j$(nproc) && \
    make DESTDIR=${SYSROOT_DIR} install_sw && cd .. && rm -rf openssl-1.1.1u

# needs openssl
ADD --chown=builder:builder https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz .
RUN tar xf libevent-2.1.12-stable.tar.gz && rm libevent-2.1.12-stable.tar.gz
RUN . tc/compile-envs && cd libevent-2.1.12-stable && \
    ./configure --build=aarch64-linux-gnu --host=${CROSS_TRIPLET}  --prefix="${INSTALL_PREFIX}" --enable-shared && \
    make && DESTDIR=${SYSROOT_DIR} make install && cd .. && rm -rf libevent-2.1.12-stable

# tmux won't run without locales. ah well.
# ADD --chown=builder:builder https://github.com/tmux/tmux/releases/download/3.4/tmux-3.4.tar.gz .
# RUN tar xf tmux-3.4.tar.gz && rm tmux-3.4.tar.gz
# RUN . tc/compile-envs && cd tmux-3.4 && \
#     ./configure --build=aarch64-linux-gnu --host=${CROSS_TRIPLET}  --prefix="${INSTALL_PREFIX}" && \
#     make && DESTDIR=${SYSROOT_DIR} make install && cd .. && rm -rf tmux-3.4

RUN . tc/compile-envs && cd Python-3.12.5 && \
    mkdir -p build/kobo && \
    cd build/kobo && \
    ../../configure \
        --build=aarch64-linux-gnu \
        --host=${CROSS_TRIPLET} \
        --prefix="${INSTALL_PREFIX}" \
        --disable-ipv6 \
        --disable-test-modules \
        --without-doc-strings \
        --enable-shared \
        --with-build-python=/home/builder/tc/python3.12/bin/python3.12 \
        --with-readline=readline \
        LDFLAGS="${LDFLAGS} -L${SYSROOT_DIR}${INSTALL_PREFIX}/lib" \
        CPPFLAGS="-I${SYSROOT_DIR}${INSTALL_PREFIX}/include" \
        ac_cv_file__dev_ptmx=yes ac_cv_file__dev_ptc=no && \
    make -j$(nproc) && \
    DESTDIR=${SYSROOT_DIR} make install
#&& cd ../../.. && rm -rf Python-3.12.5

ADD --chown=builder:builder https://www.freedesktop.org/software/libevdev/libevdev-1.13.2.tar.xz .
RUN tar xf libevdev-1.13.2.tar.xz && rm libevdev-1.13.2.tar.xz
# it's got a meson build system so let's use that
RUN cd libevdev-1.13.2 && meson rewrite kwargs set target libevdev-events install true && \
    meson rewrite kwargs set target libevdev-list-codes install true && \
    meson setup --cross-file /home/builder/tc/cross-arm-kobo.txt --prefix=${INSTALL_PREFIX} \
    -Ddefault_library=both -Dtests=disabled -Ddocumentation=disabled builddir && meson compile -C builddir && \
    DESTDIR=${SYSROOT_DIR} meson install -C builddir && cd .. && rm -rf libevdev-1.13.2

# Copy terminfo into the tabula directory
RUN cd tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot && cp -a usr/share/terminfo opt/tabula/share/ && cp -a usr/lib/terminfo opt/tabula/lib

RUN python3.12 -m crossenv --config-var CC='arm-kobo-linux-gnueabihf-gcc' --config-var CFLAGS='-std=gnu11' --machine armv7l \
    --manylinux cp312-cp312-manylinux_2_19_armv7l --manylinux cp312-cp312-manylinux_2_18_armv7l \
    --manylinux cp312-cp312-manylinux_2_17_armv7l --manylinux cp312-cp312-manylinux2014_armv7l \
    --manylinux cp312-abi3-manylinux_2_19_armv7l --manylinux cp312-abi3-manylinux_2_18_armv7l \
    --manylinux cp312-abi3-manylinux_2_17_armv7l --manylinux cp312-abi3-manylinux2014_armv7l \
    --sysroot ${SYSROOT_DIR} ${SYSROOT_DIR}/opt/tabula/bin/python3.12 cross_venv

ADD --chown=builder:builder requirements.txt .
RUN . cross_venv/bin/activate && build-pip install cffi build Cython meson-python && \
    echo "cffi" >> /home/builder/cross_venv/lib/exposed.txt && \
    echo "build" >> /home/builder/cross_venv/lib/exposed.txt && \
    echo "Cython" >> /home/builder/cross_venv/lib/exposed.txt && \
    cross-pip wheel -w pydeps -r requirements.txt --no-binary SQLAlchemy && \
    truncate -s 0 /home/builder/cross_venv/lib/exposed.txt
# Gotta force it to download the tarball for SQLAlchemy so we get the c extensions built

COPY --chown=builder:builder tabula-0.1.tar.gz .

RUN . cross_venv/bin/activate && cross-pip wheel --no-deps -w pydeps -Csetup-args="--cross-file=/home/builder/tc/cross-arm-kobo.txt" tabula-0.1.tar.gz && rm tabula-0.1.tar.gz

ADD --chown=builder:builder --chmod=777 https://astral.sh/uv/install.sh .
RUN CARGO_HOME=tc/python3.12 ./install.sh --no-modify-path && rm install.sh
# RUN tar xf uv-aarch64-unknown-linux-gnu.tar.gz && rm uv-aarch64-unknown-linux-gnu.tar.gz
RUN uv pip install -v --offline --no-cache -f pydeps/ \
    --python tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula/bin/python3.12 \
    --system --compile-bytecode tabula

# Unfortunately py-spy doesn't support Python 3.12 yet
# RUN uv pip install -v --python tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula/bin/python3.12 --system py-spy

RUN mkdir -p tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula/modules
COPY --chown=builder:builder uhid.ko tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula/modules/

COPY --chown=builder:builder process-sysroot.py .
RUN python3.12 process-sysroot.py


# We're not going to do this anymore because it's very slow when compressed and pointless when not compressed.
# RUN gensquashfs --pack-dir tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula/ \
#     --compressor xz --comp-extra arm --comp-extra armthumb tabula-full.squashfs

# RUN gensquashfs --pack-dir output/opt/tabula/ --compressor xz --comp-extra arm --comp-extra armthumb tabula.squashfs

# it's very complicated to guess the necessary FS size. just make it larger and then shrink it later.
RUN mkfs.ext2 -d tc/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/opt/tabula tabula-full.ext2.img 384m
# && resize2fs -M tabula-full.ext2.img
RUN mkfs.ext2 -d output/opt/tabula tabula.ext2.img 384m && resize2fs -M tabula.ext2.img

# Switch to root, so everything will be owned by the correct user
# USER root
# WORKDIR /root

# RUN mkdir -p /root/ocp/.adds/nm && mkdir -p /root/ocp/.adds/tabula && cp /home/builder/tabula.ext2.img /root/ocp/.adds/tabula/
# RUN cp /home/builder/aports/main/dropbear/src/dropbear-2022.83/dropbear /home/builder/aports/main/openssh/src/openssh-9.6p1/sftp-server /root/koboroot/opt/dropbear/
# COPY tabula.nm /root/ocp/.adds/nm/tabula
# COPY --chmod=755 start-tabula.sh /root/ocp/.adds/tabula/


# RUN tar czf /root/ocp/.kobo/KoboRoot.tgz -C /root/koboroot .
# RUN cd /root/ocp && zip -n tgz -r ../Dropbear.zip .


FROM scratch AS export-stage
# COPY --from=build-stage /home/builder/tabula-full.squashfs /
# COPY --from=build-stage /home/builder/tabula.squashfs /
COPY --from=build-stage /home/builder/tabula-full.ext2.img /
COPY --from=build-stage /home/builder/tabula.ext2.img /
