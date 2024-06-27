#!/usr/bin/env python3

"""
This module contains the main classes
PYFT is the file level class (read/write...)
PYFTscope contains the transformations acting on a xml
"""

import os
import sys

from pyft.tree import getDirs
from pyft.scope import PYFTscope
from pyft.util import tostring, tofortran, fortran2xml, set_verbosity, print_infos, PYFTError


class PYFT(PYFTscope):
    """
    This class extends the PYFTscope one by adding file support (read/write)
    """
    DEFAULT_FXTRAN_OPTIONS = ['-construct-tag', '-no-include', '-no-cpp', '-line-length', '9999']
    MANDATORY_FXTRAN_OPTIONS = ['-construct-tag']

    def __init__(self, filename, output=None, parser=None, parserOptions=None, verbosity=None,
                 wrapH=False, tree=None, enableCache=False):
        """
        :param filename: Input file name containing FORTRAN code
        :param output: Output file name, None to replace input file
        :param parser: path to the fxtran parser
        :param parserOptions: dictionnary holding the parser options
        :param verbosity: if not None, sets the verbosity level
        :param wrapH: if True, content of .h file is put in a .F90 file (to force
                      fxtran to recognize it as free form) inside a module (to
                      enable the reading of files containing only a code part)
        :param tree: list of directories where code can be searched for
        :param enableCache: True to cache node parents
        """
        if not sys.version_info >= (3, 8):
            #At least version 3.7 for ordered dictionary
            #At least verison 3.8 for namsepace wildcard (use of '{*}' in find or findall)
            raise PYFTError("pyft needs at least version 3.8 of python")
        self._filename = filename
        self._originalName = filename
        assert os.path.exists(filename), 'Input filename must exist'
        self._output = output
        self._parser = 'fxtran' if parser is None else parser
        self.tree = tree
        self._parserOptions = self.DEFAULT_FXTRAN_OPTIONS if parserOptions is None else parserOptions
        self._parserOptions = self._parserOptions.copy()
        for t in getDirs(self.tree):
            self._parserOptions.extend(['-I', t])
        for option in self.MANDATORY_FXTRAN_OPTIONS:
            if option not in self._parserOptions:
                self._parserOptions.append(option)
        ns, xml = fortran2xml(self._filename, self._parser, self._parserOptions, wrapH)
        super().__init__(xml, ns, enableCache=enableCache)
        if verbosity is not None:
            set_verbosity(verbosity)

    def close(self):
        print_infos()

    @property
    def xml(self):
        """
        Returns the xml as a string
        """
        return tostring(self.node)

    @property
    def fortran(self):
        """
        Returns the FORTRAN as a string
        """
        return tofortran(self.node)

    def renameUpper(self):
        """
        The output file will have an upper case extension
        """
        self._rename(str.upper)

    def renameLower(self):
        """
        The output file will have a lower case extension
        """
        self._rename(str.lower)

    def _rename(self, mod):
        """
        The output file will have a modified extension.
        :param mod: function to apply to the file extension
        """
        def _trans_ext(path, mod):
            p, e = os.path.splitext(path)
            return p + mod(e)
        if self._output is None:
            self._filename = _trans_ext(self._filename, mod)
        else:
            self._output = _trans_ext(self._output, mod)

    def write(self):
        """
        Writes the output FORTRAN file
        """
        with open(self._filename if self._output is None else self._output, 'w') as f:
            f.write(self.fortran)
        if self._output is None and self._filename != self._originalName:
            #We must perform an in-place update of the file, but the output file
            #name has been updated. Then, we must remove the original file.
            os.unlink(self._originalName)

    def writeXML(self, filename):
        """
        Writes the output XML file
        :param filename: XML output file name
        """
        with open(filename, 'w') as f:
           f.write(self.xml)

    def getFileName(self):
        """
        :return: the name of the input file name or 'unknown' if not available
                 in the xml fragment provided
        """
        return self.find('.//{*}file').attrib['name']
