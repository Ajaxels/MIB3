%PEETError     Raise an error from MatTomo code
%
%   PEETError(message)
%   PEETError(format, ...)
%
%   Supplied by MIB, not by MatTomo. MatTomo reports every failure through
%   PEETError, which lives in the wider PEET (Particle Estimation for
%   Electron Tomography) distribution; MIB bundles only the MatTomo subset,
%   so without this shim any MatTomo failure surfaced as
%   "Undefined function 'PEETError' for input arguments of type 'char'"
%   and the real reason was lost.
%
%   A single argument is passed through LITERALLY rather than as a format
%   template: most one-argument call sites embed a filename, and on Windows
%   sprintf would eat the backslashes ("C:\temp\x.mrc" -> "C:<tab>emp...").
%   Two or more arguments are formatted with sprintf, which is what those
%   call sites expect.
%
%   Bugs: none known

function PEETError(message, varargin)

if nargin > 1
    message = sprintf(message, varargin{:});
end
error('MatTomo:PEETError', '%s', message);
