%PEETWarning   Issue a warning from MatTomo code
%
%   PEETWarning(message)
%   PEETWarning(format, ...)
%
%   Supplied by MIB, not by MatTomo - see PEETError for why. Same argument
%   handling: one argument is literal, several are formatted with sprintf.
%
%   Bugs: none known

function PEETWarning(message, varargin)

if nargin > 1
    message = sprintf(message, varargin{:});
end
warning('MatTomo:PEETWarning', '%s', message);
