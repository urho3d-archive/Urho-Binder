#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <pybind11/operators.h>
#include <memory>

<%
#Global declarations:
def varsafe(s):
    return s.replace('::','_').replace('<','_').replace('>','').replace(' ','_')
    
operator_typedefs = [
    'unsigned long long',
    'unsigned int',
    'unsigned short',
    'unsigned long',
    'long long',
]
override_dict = {}
for td in operator_typedefs:
    override_dict[td] = td.replace(' ','')
    
    
def type(t):
    return override_dict[t] if override_dict.has_key(t) else t
    
def construct(t):
    t = type(t)
    #TODO: must not use stripped type for the pointer version, as const char* != char*
    return ('((%s)0)' % t )if t[-1] == '*' else (t + '()')

%>\


% for td in operator_typedefs:
typedef ${td} ${override_dict[td]};
% endfor

#include "String_binding.h"

/*#include "${file}"*/
#include "Urho3DAll.h"

namespace py = pybind11;

PYBIND11_MODULE(urho, m) {

% for ns in namespaces:
//-------------------------------------------
% if ns['namespace']:
// Export ${ns['namespace']} namespace as a class
% else:
// Export global namespace
% endif
//-------------------------------------------
% if not ns['force-global']:
<%
    name = ns['namespace']
    fakemodule = 'PythonBindingsFakeModule' + ''.join(ns['parents']) + name
    pyns = 'pyclass_NS_' + varsafe(ns['full-namespace'])
    #Need the \ at the end of python blocks to consume the newline
%>\

class ${fakemodule} {};

auto ${pyns} = py::class_<${fakemodule}>(m, "${name}")
  // Functions
% for fn in ns['functions']:
<% 
    func = fn['func']
    decl = '(%s (*)(%s))' % (fn['ret'], fn['arg-types'])
    fnptr = '%s &%s::%s' % (decl, ns['full-namespace'], func)
    args = ''
    for arg in fn['args']:
        if arg.has_key('default-val'):
            args += ', py::arg("%s")=%s' % (arg['name'], arg['default-val'])
        else:
            args += ', py::arg("%s")' % arg['name']
%>\
% if not(fn.has_key('variadic') or len(fn['pointer-count']) > 1):
  .def_static("${func}", ${fnptr}, "todo: docstring"${args})
% endif
% endfor #functions
  // Variables
  
## TODO: // Returns c-style int[5]:
## m.def("func_a", []() { int *ret = func_a(); return std::vector<int>(ret, ret + 5); });
##// Takes c-style int[5]:
##m.def("func_b", [](std::array<int, 5> a) { return func_b(a.data()); });
% for v in ns['vars']:
<% 
    var = v['var']
    ptr = '&%s::%s' % (ns['full-namespace'], var)
    isarray = v['type'][-1] == ']'
    if isarray:
        pass #todo: finish
%>\
% if not v['reference'] and not isarray: ##Cannot take address of reference
% if v['const']:
  .def_readonly_static("${var}", ${ptr}, "todo: var docstring")
% else:
  .def_readwrite_static("${var}", ${ptr}, "todo: var docstring")
% endif
% else:
 // Cannot bind ${ptr} TODO: def_property with lambdas for it
% endif
% endfor ##Variables
; // End Namespace Class ${name}
% else: #Force Global is true
<% ####################################################################
    name = ns['namespace']
    pyns = 'pyclass_NS_' + varsafe(ns['full-namespace'])
%>\
auto ${pyns} = m
  // Functions
% for fn in ns['functions']:
<% 
    func = fn['func']
    decl = '(%s (*)(%s))' % (fn['ret'], fn['arg-types'])
    fnptr = '%s &%s::%s' % (decl, ns['full-namespace'], func)
    args = ''
    for arg in fn['args']:
        if arg.has_key('default-val'):
            args += ', py::arg("%s")=%s' % (arg['name'], arg['default-val'])
        else:
            args += ', py::arg("%s")' % arg['name']
%>\
% if not(fn.has_key('variadic') or len(fn['pointer-count']) > 1):
  .def("${func}", ${fnptr}, "todo: docstring"${args})
% endif
% endfor #Fuctions
; // close namespace ${name} class functions
  // Variables
% for v in ns['vars']:
<%  var = v['var']  %>\
  ${pyns}.attr("${var}") = ${ns['full-namespace']}::${var}; // todo: attr docstring
% endfor #Variables
% endif
  // Namespace vars class ${name}

  // Forward-declare class variables TODO: Must be moved before functions and attributes of namespace
% for cls in ns['classes']:
<% 
    classname = cls['classname']
    fullclass = cls['class']
    if fullclass == 'Urho3D::AnimatableAnimatable':
        print cls
        raise Exception("a;lksd")
    fakemodule = 'PythonBindingsFakeModule' + ''.join(ns['parents']) + classname
    pyclass = 'pyclass_Var_' + varsafe(cls['class'])
    baseclass = ('pyclass_' + 'Var_' + varsafe(cls['outer'][-1])) if cls['outer'] else pyns
    ptrclass = (', SharedPtr<%s>' % fullclass) if cls['ref-counted'] else ''
    inherits = ''.join([', ' + x['base'] for x in cls['inherits'] ])
#    print (fullclass, ptrclass, inherits)
#    print fullclass + ptrclass + inherits
%>// Class ${classname}
auto ${pyclass} = py::class_<${fullclass + ptrclass + inherits}>(${baseclass}, "${classname}", "test doc");
% endfor #Class Pre-registration

  // Register class details
% for cls in ns['classes']:

<% 
    classname = cls['classname']
    fullclass = cls['class']
    fakemodule = 'PythonBindingsFakeModule' + ''.join(ns['parents']) + classname
    pyclass = 'pyclass_Var_' + varsafe(cls['class'])
    baseclass = ('pyclass_' + 'Var_' + varsafe(cls['outer'][-1])) if cls['outer'] else pyns
    ptrclass = (', SharedPtr<%s>' % fullclass) if cls['ref-counted'] else ''
    inherits = ', '.join([ x['base'] for x in cls['inherits'] ])
%>// Class ${classname}
  ${pyclass}
% if cls.has_key('ctors'):
  // Constructors
% for fn in cls['ctors']:
% if not(fn.has_key('variadic') or len(fn['pointer-count']) > 1 or fn.has_key('friend')):
  .def(py::init<${fn['arg-types']}>(), "todo: docstring")
% endif
% endfor
% else: ## Assume that it is default constructed
  .def(py::init<>(), "todo: docstring")
% endif
  // Methods
% for fn in cls['methods']:
<%
    func = fn['func']
    if fn['static']:
        decl = '(%s (*)(%s)%s)' % (fn['ret'], fn['arg-types'], fn['const'])
    else:
        decl = '(%s (%s::*)(%s)%s)' % (fn['ret'],fullclass, fn['arg-types'], fn['const'])
    fnptr = '%s &%s::%s' % (decl, fullclass, func)
    args = ''
    for arg in fn['args']:
        if arg.has_key('default-val'):
            args += ', py::arg("%s")=%s' % (arg['name'], arg['default-val'])
        else:
            args += ', py::arg("%s")' % arg['name']
%>\
% if not(fn.has_key('variadic') or len(fn['pointer-count']) > 1 or fn.has_key('friend')):
    % if fn['static']:
  .def_static("${func}", ${fnptr}, "todo: docstring"${args})
    % else:
  .def("${func}", ${fnptr}, "todo: docstring"${args})
    % endif
% endif
% endfor ##Methods
  // Operators
% for op in cls['operators']:
% if op['op-name'] not in ['assign','pre_inc','post_inc','inc','pre_dec','post_dec','dec']:
##if not op.has_key('assign'):
<%
    func = op['func']
    o = op['op']
    if op['static']:
        decl = '(%s (*)(%s))' % (op['ret'], op['arg-types'])
    else:
        decl = '(%s (%s::*)(%s))' % (op['ret'],fullclass, op['arg-types'])
    fnptr = '%s &%s::%s' % (decl, fullclass, func)
    args = op['args']
    style = op['op-style'] # unary, binary, post_unary, operator, cast
%>\
// OP ${func} len ${len(args)}
% if style == 'unary':
  .def(${o}py::self, "todo: docstring")
% elif style == 'post_unary':
  .def(py::self${o}, "todo: docstring")
% elif style == 'binary':
    <% if (len(args) == 0): raise Exception('Somats Brokeded for ' + func + fullclass + op['friend'] + op['arg-types'] + op['ret']) %>\
    % if (len(args) == 1 and args[0]['self']) or (len(args) == 2 and args[0]['self'] and args[1]['self']):
  .def(py::self ${o} py::self, "todo: docstring")
    % elif len(args) == 1:
  .def(py::self ${o} ${args[0]['stripped-type'] | construct}, "todo: docstring")
    % elif args[0]['self']:
  .def(py::self ${o} ${args[1]['stripped-type'] | construct}, "todo: docstring")
    % elif args[1]['self']:
  .def(${args[0]['stripped-type'] | construct} ${o} py::self, "todo: docstring")
    % else:
// implement ${func} for ${args}
    % endif
% elif style == 'post_unary':
  .def(py::self${o}, "todo: docstring")
% elif style == 'operator':
<%
    if op['friend'] and args and args[0]['self']:
        declargs = ', '.join([(', %s arg%d' % (arg['type'],i)) for i,arg in enumerate(op['args'])])
        callargs = ', '.join([('arg%d' % i) for i in range(1,len(op['args']))])
    else:
        declargs = '%s %s& arg0' % (op['const'],fullclass) + ''.join([(', %s arg%d' % (arg['type'],i+1)) for i,arg in enumerate(op['args'])])
        callargs = ', '.join([('arg%d' % i) for i in range(len(op['args'])+1)])
    caller = 'arg0'
    call = o[0] + callargs + o[1]
    pyfuncname = '__getitem__' if op.has_key('index') else '__call__'
%>\
  .def("${pyfuncname}",[](${declargs}) { return ${caller}${call};}, "todo: docstring, argnames", py::is_operator())
% elif style == 'cast':
  .def((${o})py::self, "todo: docstring")
% else:
// implement ${func} for ${args}
% endif # Operator switch
% endif # skip assign
% endfor ##Methods
  // Variables
% for v in cls['vars']:
<% 
    var = v['var']
    ptr = '&%s::%s' % (fullclass, var)
    isarray = v['type'][-1] == ']'
    ptr2 = '**' in v['type']
%>\
% if not v['reference'] and not isarray and not ptr2: ##Cannot take address of reference
% if v['const'] and v['static']:
  .def_readonly_static("${var}", ${ptr}, "todo: var docstring")
% elif v['static']:
  .def_readwrite_static("${var}", ${ptr}, "todo: var docstring")
% elif v['const']:
  .def_readonly("${var}", ${ptr}, "todo: var docstring")
% else:
  .def_readwrite("${var}", ${ptr}, "todo: var docstring")
% endif
% else:
 // Cannot bind ${ptr} TODO: def_property with lambdas for it
% endif
% endfor ##Variables
; // End Class ${classname}
% endfor ##Classes

% endfor ##Namespaces

}
