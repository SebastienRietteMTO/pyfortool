"""
This module includes functions to deal with expressions
These functions are independent of the PYFT and PYFTscope objects
"""

import re
from functools import lru_cache
import copy

import xml.etree.ElementTree as ET
from pyft.util import debugDecor, isint, isfloat, fortran2xml, PYFTError
from pyft import NAMESPACE


def createElem(tagName):
    """
    :param tagName: tag of the element to create
    """
    return ET.Element(f'{{{NAMESPACE}}}{tagName}')


@lru_cache
def _cached_createExprPart(value):
    """
    :param value: expression part to put in a *-E node

    If value is:
      - a FORTRAN string (python sting containing a ' or a "), returns
        <f:string-E><f:S>...
      - a FORTRAN value (python string convertible in real or int, or .FALSE./.TRUE.), returns
        <f:literal-E><f:l>...
      - a FORTRAN variable name (pyhon string with only alphanumerical characters and _), returns
        <named-E/><N><n>...
      - a FORTRAN operation (other python string), returns the right part of the X affectation statement
        of the code: "SUBROUTINE T; X=" + value + "; END". The xml is obtained by calling fxtran.
    """

    #Allowed characters in a FORTRAN variable name
    allowed = "abcdefghijklmnopqrstuvwxyz"
    allowed += allowed.upper() + '0123456789_'

    if isint(value) or isfloat(value) or value.upper() in ('.TRUE.', '.FALSE.'):
        l = createElem('l')
        l.text = str(value)
        node = createElem('literal-E')
        node.append(l)
    elif "'" in value or '"' in value:
        S = createElem('S')
        S.text = value
        node = createElem('string-E')
        node.append(S)
    elif all([c in allowed for c in value]):
        n = createElem('n')
        n.text = value
        N = createElem('N')
        N.append(n)
        node = createElem('named-E')
        node.append(N)
    elif re.match(r'[a-zA-Z_][a-zA-Z0-9_]*%[a-zA-Z_][a-zA-Z0-9_]*$', value):
        #A%B
        n = createElem('n')
        n.text = value.split('%')[0]
        N = createElem('N')
        N.append(n)
        ct = createElem('ct')
        ct.text = value.split('%')[1]
        componentR = createElem('component-R')
        componentR.text = '%'
        componentR.append(ct)
        RLT = createElem('R-LT')
        RLT.append(componentR)
        node = createElem('named-E')
        node.append(N)
        node.append(RLT)
    else:
        _, xml = fortran2xml("SUBROUTINE T; X={v}; END".format(v=value))
        node = xml.find('.//{*}E-2')[0]
    return node

@debugDecor
def createExprPart(value):
    """
    :param value: expression part to put in a *-E node

    If value is:
      - a FORTRAN string (python sting containing a ' or a "), returns
        <f:string-E><f:S>...
      - a FORTRAN value (python string convertible in real or int, or .FALSE./.TRUE.), returns
        <f:literal-E><f:l>...
      - a FORTRAN variable name (pyhon string with only alphanumerical characters and _), returns
        <named-E/><N><n>...
      - a FORTRAN operation (other python string), returns the right part of the X affectation statement
        of the code: "SUBROUTINE T; X=" + value + "; END". The xml is obtained by calling fxtran.
    """
    return copy.deepcopy(_cached_createExprPart(value))

@debugDecor
def createExpr(value):
    """
    :param value: statements to convert into xml
    :return: the xml fragment corresponding to value (list of nodes)
    """
    return fortran2xml("SUBROUTINE T\n{v}\nEND".format(v=value))[1].find('.//{*}program-unit')[1:-1]

@debugDecor
def simplifyExpr(expr, add=None, sub=None):
    """
    :param expr: string containing an expression to simplify
    :param add: string containing an expression to add
    :param sub: string containing an expression to substract
    :return: simplified expression
    E.g. simplifyExpr('1+1+I+JI-I') => '2+JI'
    Note: only additions and substractions are considered
          addition and subtraction within parentheses are forbidden
    """
    #We could have used external module, such as sympy, but this routine (as long as it's sufficient)
    #avoids introducing dependencies.
    if re.search('\([^()]*[+-][^()]*\)', expr):
        raise NotImplementedError("Expression cannot (yet) contain + or - sign inside parenthesis: {expr}".format(expr=expr))

    def split(expr):
        """
        :param s: expression
        :return: a list of (sign, abs(value))
        """
        splt = re.split('([+-])', expr.replace(' ', '').upper()) #['1', '+', '1', '+', 'I', '+', 'JI', '-', 'I']
        if splt[0] == '':
            #'-1' returns [
            splt = splt[1:]
        if len(splt) % 2 == 1:
            #expr doesn't start with a sign
            splt = ['+'] + splt #['+', '1', '+', '1', '+', 'I', '+', 'JI', '-', 'I']
        #group sign and operand [('+', '1'), ('+', '1'), ('+', 'I'), ('+', 'JI'), ('-', 'I')]
        splt = [(splt[2 * i], splt[2 * i + 1]) for i in range(len(splt) // 2)]
        return splt

    splt = split(expr)
    if add is not None:
        splt += split(add)
    if sub is not None:
        splt += [('-' if sign == '+' else '+', elem) for (sign, elem) in split(sub)]
    #Suppress elements with opposite signs
    for sign, elem in splt.copy():
        if ('+', elem) in splt and ('-', elem) in splt:
            splt.remove(('+', elem))
            splt.remove(('-', elem))
    #Pre-compute integer additions/substractions
    found = -1
    for i, (sign, elem) in enumerate(splt.copy()):
        if isint(elem):
            if found == -1:
                found = i
            else:
                result = str((1 if splt[found][0] == '+' else -1) * int(splt[found][1]) + \
                             (1 if sign == '+' else -1) * int(elem))
                splt[found] = split(str(result))[0]
                splt.pop(i)
    #Order (no matter what ordering is done but we need to order to allow comparisons)
    splt.sort(key=lambda s: ''.join(s))
    #Empty e.g. '1-1'
    if len(splt) == 0:
        splt = [('+', '0')]
    #Concatenate
    s = ' '.join(s[0] + ' ' + s[1] for s in splt)
    if s.startswith('+'):
        s = s[1:]
    return s.lstrip(' ')

@debugDecor
def createArrayBounds(lowerBoundstr, upperBoundstr, context):
    """
    Return a lower-bound and upper-bound node
    :param lowerBoundstr: string for the fortran lower bound of an array
    :param upperBoundstr: string for the fortran upper bound of an array
    :param context: 'DO' for DO loops
                    'DOCONCURRENT' for DO CONCURRENT loops
                    'ARRAY' for arrays
    """
    lowerBound = createElem('lower-bound')
    lowerBound.insert(0, createExprPart(lowerBoundstr))
    upperBound = createElem('upper-bound')
    upperBound.insert(0, createExprPart(upperBoundstr))
    if context == 'DO':
        lowerBound.tail = ', '
    elif context in ('DOCONCURRENT', 'ARRAY'):
        lowerBound.tail = ':'
    else:
        raise PYFTError('Context unknown in createArrayBounds: {c}'.format(c=str(context)))
    return lowerBound, upperBound
