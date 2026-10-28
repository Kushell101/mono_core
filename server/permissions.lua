function HasPermission(source, permission)
    source = tonumber(source)

    if not source or type(permission) ~= 'string' or permission == '' then
        return false
    end

    if source == 0 then
        return true
    end

    return IsPlayerAceAllowed(source, permission) and true or false
end

exports('HasPermission', HasPermission)