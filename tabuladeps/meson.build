project('tabuladeps', 'c')

stage = get_option('stage')

if stage == 'one'
    zlib = subproject('zlib')
    zlib_dep = zlib.get_variable('zlib_dep')
    meson.override_dependency('zlib', zlib_dep)
    libpng = subproject('libpng')
    subproject('freetype2')
    subproject('glib')
elif stage == 'two'
    subproject('libffi')
    subproject('icu', default_options: 'cpp_std=c++14')
    subproject('harfbuzz', default_options: 'tests=disabled')
elif stage == 'three'
    subproject('freetype2')
    subproject('fontconfig')
    subproject('pixman', default_options: 'tests=disabled')
    subproject('cairo', default_options: ['tests=disabled', 'zlib=disabled'])
    subproject('pango')
    subproject('sqlite3')
endif