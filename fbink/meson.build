project(
    'fbink',
    'c',
    version: '1.25.0',
    default_options: [
        'warning_level=2',
        'b_lto=true',
        'buildtype=release',
        'b_ndebug=if-release',
        'b_staticpic=false',
        'c_std=gnu17,gnu11',
    ],
)
pkg = import('pkgconfig')

# We don't need to do magic to detect the toolchain; meson uses cross files.
cc_is_cross = meson.is_cross_build()
compiler = meson.get_compiler('c')
cc_is_clang = compiler.get_id() == 'clang'
if compiler.get_id() not in ['gcc', 'clang']
    warning(
        'Expected a GCC or clang compiler, but found',
        compiler.get_id(),
        'instead. Results may be unpredictable.',
    )
endif
moar_warnings = cc_is_clang or (
    compiler.get_id() == 'gcc'
    and compiler.version().version_compare('>=7.0.0')
)
if not moar_warnings
    message(
        'Turning off extra compiler warnings because this is an old (or unexpected) compiler.',
    )
endif
# cc_is_musl is much harder to detect properly… https://gist.github.com/unmanned-player/f2421eec512d610116f451249cce5920
# can use https://musl.cc/ as toolchains for a test probably
# it turns out what we want is to error if -fuse-linker-plugin is not supported when LTO is enabled. so let's do that.
uses_lto = get_option('b_lto')
if uses_lto
    if not compiler.has_link_argument('-fuse-linker-plugin')
        error(
            'LTO build specified, but the linker does not support linker plugins. (This is common in musl toolchains.)',
        )
    endif
    add_project_link_arguments('-fuse-linker-plugin', language: ['c'])
endif

will_build_shared = get_option('default_library') in ['shared', 'both']
will_build_static = get_option('default_library') in ['static', 'both']

if not get_option('debug')
    if (will_build_shared or get_option('b_staticpic')) and not cc_is_clang
        # Don't hobble GCC just for the sake of being interposable
        # Applies when building a shared library as well as just PIC in general.
        # Fun fact: apparently the default on Clang ;).
        # However, not supported below GCC 5.
        if compiler.has_argument('-fno-semantic-interposition')
            add_project_arguments('-fno-semantic-interposition', language: ['c'])
        endif
    endif
    # Enable loop unrolling & vectorization in the hope it'll do something smart with our pixel loops
    add_project_arguments('-ftree-vectorize', '-funroll-loops', language: ['c'])
    if not cc_is_clang
        # Always match GCC >= 10 new default
        add_project_arguments('-fno-common', language: ['c'])
    endif
endif

if moar_warnings
    add_project_arguments('-Wunused', '-Wformat=2', '-Wformat-signedness', language: ['c'])
    # NOTE: -Wformat-truncation=2 is still a tad too aggressive w/ GCC 9, so, tone it down to avoid false-positives...
    add_project_arguments('-Wformat-truncation=1', language: ['c'])
    if not uses_lto and not cc_is_cross
        # NOTE: GCC 9 is more verbose, so nerf that, too, when building w/o LTO on native systems...
        add_project_arguments('-Wno-stringop-truncation', language: ['c'])
    endif
    add_project_arguments('-Wnull-dereference', '-Wuninitialized', language: ['c'])
    if uses_lto
        # NOTE: Inlining put_pixel in fbink_print_ot triggers a few -Wmaybe-uninitialized when we pass grayscale pixels...
        #       Actually harmless, because they trip in an RGB565 codepath, which we make sure always get fed RGB32.
        #       Unfortunately, since they're tripped at link-time, I can't pragma'em away :/.
        add_project_arguments('-Wno-maybe-uninitialized', language: ['c'])
    endif
    add_project_arguments(
        '-Wduplicated-branches',
        '-Wduplicated-cond',
        '-Wundef',
        '-Wbad-function-cast',
        '-Wwrite-strings',
        '-Wjump-misses-init',
        '-Wlogical-op',
        '-Wstrict-prototypes',
        '-Wold-style-definition',
        '-Wshadow',
        '-Wmissing-prototypes',
        '-Wmissing-declarations',
        '-Wnested-externs',
        '-Winline',
        '-Wcast-qual',
        # NOTE: GCC 8 introduces -Wcast-align=strict to warn regardless of the target architecture (i.e., like clang)
        '-Wcast-align',
        '-Wconversion',
        language: ['c'],
    )

    if get_option('debug')
        # Output padding info when debugging (NOTE: Clang is slightly more verbose)
        # As well as function attribute hints
        add_project_arguments(
            '-Wpadded',
            '-Wsuggest-attribute=pure',
            '-Wsuggest-attribute=const',
            '-Wsuggest-attribute=noreturn',
            '-Wsuggest-attribute=format',
            '-Wmissing-format-attribute',
            language: ['c'],
        )
    endif
    # And disable this, because it obviously doesn't play well with using goto to handle cleanup on error codepaths...
    add_project_arguments('-Wno-jump-misses-init', language: ['c'])
    # And just because that's annoying...
    if cc_is_clang
        # possibly this should be put into the crossfile though
        add_project_arguments(
            '-Wno-ignored-optimization-argument',
            '-Wno-unknown-warning-option',
            language: ['c'],
        )
    endif
endif

# Assume we'll be safe to use by threaded applications...
# We're Linux-bound anyway...
add_project_arguments('-D_REENTRANT=1', '-D_GNU_SOURCE', language: ['c'])

# And with our own rpath for standalone distribution
# ifdef STANDALONE
# 	EXTRA_LDFLAGS+=-Wl,-rpath=/usr/local/fbink/lib
# endif

# Who uses legacy kindle anyway… We would need to set both -DFBINK_FOR_KINDLE and -DFBINK_FOR_LEGACY and that's annoying.
device_flags = {
    'kindle': '-DFBINK_FOR_KINDLE',
    'cervantes': '-DFBINK_FOR_CERVANTES',
    'generic-linux': '-DFBINK_FOR_LINUX',
    'kobo': '-DFBINK_FOR_KOBO',
    'remarkable': '-DFBINK_FOR_REMARKABLE',
    'pocketbook': '-DFBINK_FOR_POCKETBOOK',
}
add_project_arguments(device_flags[get_option('device')], language: ['c'])

# A version tag...
# https://mesonbuild.com/Reference-manual_functions.html#vcs_tag has a better way to do this but it requires generating a source file
# So for the moment we'll just use meson.project_version()
version_template = {
    'kindle': '-DFBINK_VERSION="@0@ for Kindle"',
    'cervantes': '-DFBINK_VERSION="@0@ for Cervantes"',
    'generic-linux': '-DFBINK_VERSION="@0@ for Linux"',
    'kobo': '-DFBINK_VERSION="@0@ for Kobo"',
    'remarkable': '-DFBINK_VERSION="@0@ for reMarkable"',
    'pocketbook': '-DFBINK_VERSION="@0@ for PocketBook"',
}
add_project_arguments(
    version_template[get_option('device')].format(meson.project_version()),
    language: ['c'],
)

# feature flag time
draw_opt = get_option('draw')
bitmap_opt = get_option('bitmap_fonts').require(
    draw_opt.allowed(),
    error_message: 'Bitmap fonts require drawing primitives',
)
extra_fonts_opt = get_option('extra_fonts').require(
    bitmap_opt.allowed(),
    error_message: 'Extra bitmap fonts require bitmap font support',
)
unifont_opt = get_option('unifont').require(
    bitmap_opt.allowed(),
    error_message: 'GNU Unifont requires bitmap font support',
)
image_opt = get_option('image').require(
    draw_opt.allowed(),
    error_message: 'Image support requires drawing primitives',
)
opentype_opt = get_option('opentype').require(
    draw_opt.allowed(),
    error_message: 'OTF/TTF support requires drawing primitives',
)
button_scan_opt = get_option('button_scan').require(
    get_option('device') == 'kobo',
    error_message: 'Button scan support only works on Kobo',
)
add_project_arguments('-DFBINK_MINIMAL', language: ['c'])
if draw_opt.allowed()
    add_project_arguments('-DFBINK_WITH_DRAW', language: ['c'])
endif
if bitmap_opt.allowed()
    add_project_arguments('-DFBINK_WITH_BITMAP', language: ['c'])
endif
if extra_fonts_opt.allowed()
    add_project_arguments('-DFBINK_WITH_FONTS', language: ['c'])
endif
if unifont_opt.allowed()
    add_project_arguments('-DFBINK_WITH_UNIFONT', language: ['c'])
endif
if image_opt.allowed()
    add_project_arguments('-DFBINK_WITH_IMAGE', language: ['c'])
endif
if opentype_opt.allowed()
    add_project_arguments('-DFBINK_WITH_OPENTYPE', language: ['c'])
endif
if button_scan_opt.allowed()
    add_project_arguments('-DFBINK_WITH_BUTTON_SCAN', language: ['c'])
endif

# NOTE: Always use as-needed to avoid unecessary DT_NEEDED entries :)
add_project_link_arguments('-Wl,--as-needed', language: ['c'])

# # Pick up our vendored build of libunibreak, if requested
# ifdef UNIBREAK
# 	EXTRA_LDFLAGS+=-Llibunibreak-staged/src/.libs
# 	LIBS+=-l:libunibreak.a
# 	SHARED_LIBS+=-l:libunibreak.a
# endif

lib_deps = []
if get_option('device') == 'kobo'
    # Everything we build will need this on Kobo
    i2c_tools = subproject(
        'i2c-tools',
        default_options: {
            'default_library': 'static',
            'c_args': '-Wno-sign-conversion',
            'b_staticpic': will_build_shared,
        },

    )
    libi2c_dep = i2c_tools.get_variable('i2c_dep')
    lib_deps += libi2c_dep
endif

if get_option('device') == 'pocketbook'
    lib_deps += dependency('dl')
endif

lib_src = [files('fbink.c'), files('cutef8/utf8.c'), files('cutef8/dfa.c')]
if opentype_opt.allowed()
    lib_src += [
        files('libunibreak/src/linebreak.c'),
        files('libunibreak/src/linebreakdata.c'),
        files('libunibreak/src/unibreakdef.c'),
        files('libunibreak/src/linebreakdef.c'),
    ]
    # NOTE: Despite attempts at using mostly GCC builtins, OpenType support needs lm
    lib_deps += compiler.find_library('m')
endif
if image_opt.allowed()
    lib_src += [files('qimagescale/qimagescale.c')]
endif

fbink_lib = library(
    'fbink',
    lib_src,
    version: meson.project_version(),
    dependencies: lib_deps,
    pic: true,
    c_shared_args: ['-DFBINK_SHAREDLIB'],
    install: true,
)
install_headers('fbink.h')
pkg.generate(fbink_lib)

executable(
    'fbink',
    files('fbink_cmd.c'),
    link_with: [fbink_lib],
    install: true,
)

executable(
    'button_scan',
    files('button_scan_cmd.c'),
    build_by_default: button_scan_opt.allowed(),
    link_with: [fbink_lib],
)

executable(
    'fbdepth',
    files('utils/fbdepth.c'),
    build_by_default: false,
    link_with: [fbink_lib.get_static_lib()],
)