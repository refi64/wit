from os.path import join, dirname, splitext
import sys, glob, subprocess, difflib

def get_bounds(data, begin):
    st = data.index(begin)
    p = data.index('#', st)
    return '\n'.join(data[data.index(begin)+1:p])

def main(wit):
    for test in glob.iglob(join(dirname(__file__), '*.wit')):
        name = splitext(test)[0]
        print(name)
        with open(test) as f:
            testdata = list(map(str.rstrip, f.readlines()))
        exout = get_bounds(testdata, '_STDOUT')
        exerr = get_bounds(testdata, '_STDERR')
        p = subprocess.Popen([wit], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        out, err = map(lambda x: x.decode('ascii').strip(),
            p.communicate(input=bytes('\n'.join(testdata)+'\n', 'ascii')))
        if exout != out or exerr != err:
            print('TEST FAILED')
            print('STDOUT:')
            print('\n'.join(difflib.ndiff(exout.split('\n'), out.split('\n'))))
            print('STDERR:')
            print('\n'.join(difflib.ndiff(exerr.split('\n'), err.split('\n'))))

if __name__ == '__main__':
    main(*sys.argv[1:])
