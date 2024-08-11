install_man('libi2c.3')

mapfile = 'libi2c.map'
vflag = '-Wl,--version-script,@0@/@1@'.format(meson.current_source_dir(), mapfile)

i2c_lib = library(
    'i2c',
    files('smbus.c'),
    include_directories: inc,
    version: '0.1.1',
    link_args: vflag,
    link_depends: mapfile,
    c_args: [
        '-Wstrict-prototypes',
        '-Wshadow',
        '-Wpointer-arith',
        '-Wcast-qual',
        '-Wcast-align',
        '-Wwrite-strings',
        '-Wnested-externs',
        '-Winline',
        '-Wundef',
        '-Wmissing-prototypes',
    ],
    c_shared_args: ['-D_REENTRANT'],
    override_options: {'warning_level': '2'},
    install: true,
    pic: true,
)
i2c_dep = declare_dependency(include_directories: inc, link_with: i2c_lib)
meson.override_dependency('i2c', i2c_dep)