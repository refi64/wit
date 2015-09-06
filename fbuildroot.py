from fbuild.target import register
from fbuild.path import Path
import fbuild, sys

@fbuild.db.caches
def crystal(ctx, srcs: fbuild.db.SRCS, dst) -> fbuild.db.DST:
    dst = Path.addroot(dst, ctx.buildroot)
    ctx.execute(['crystal', 'build', '-o', dst, srcs[0]], 'crystal',
        '%s -> %s' % (' '.join(srcs), dst), color='yellow')
    return dst

def build(ctx):
    global wit
    wit = crystal(ctx, ['wit.cr'] + Path.glob('wit/*.cr'), 'wit')
    ctx.execute('cat prog.wit | %s' % wit, 'wit', 'prog.wit', shell=True)

@register()
def assemble(ctx):
    ctx.execute('cat prog.wit | build/wit > build/prog.asm', 'wit', 'prog.wit',
        shell=True)
    ctx.execute('nasm -f elf64 build/prog.asm -o build/x.o', 'nasm',
        'build/prog.asm -> build/x.o', shell=True)
    ctx.execute('ld -o build/x build/x.o', 'ld', 'build/x.o -> build/x',
        shell=True)

@register()
def test(ctx):
    build(ctx)
    ctx.execute([sys.executable, 'tests/run.py', wit])
