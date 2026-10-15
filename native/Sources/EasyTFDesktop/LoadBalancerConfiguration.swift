import Foundation

enum LoadBalancerConfiguration {
    static func targetGroup(network: Bool) -> JSONValue {
        .object(["port": .number(80), "protocol": .string(network ? "TCP" : "HTTP"), "target_type": .string("instance"),
                 "instance_keys": .array([]), "existing_target_ids": .array([]), "tags": .object([:]),
                 "health_check": .object(["protocol": .string(network ? "TCP" : "HTTP"), "port": .string("traffic-port"),
                     "path": network ? .null : .string("/"), "matcher": network ? .null : .string("200"),
                     "interval": .number(30), "timeout": .number(5), "healthy_threshold": .number(3), "unhealthy_threshold": .number(3)])])
    }
    static func listener(network: Bool, target: String) -> JSONValue {
        .object(["port": .number(80), "protocol": .string(network ? "TCP" : "HTTP"), "target_group_key": .string(target), "certificate_arn": .null, "ssl_policy": .null])
    }
    static func make(name: String, network: Bool) -> JSONValue {
        .object(["name": .string(name), "load_balancer_type": .string(network ? "network" : "application"), "internal": .bool(false),
                 "subnet_ids": .array([]), "existing_security_group_ids": .array([]), "security_group_keys": .array([]),
                 "deletion_protection": .bool(false), "tags": .object([:]),
                 "target_groups": .object(["web": targetGroup(network: network)]),
                 "listeners": .object(["frontend": listener(network: network, target: "web")])])
    }
    static func healthProtocol(_ protocolValue: String, health: JSONValue) -> JSONValue {
        var health = health
        health["protocol"] = .string(protocolValue)
        if protocolValue == "TCP" { health["path"] = .null; health["matcher"] = .null }
        else { if health["path"] == .null { health["path"] = .string("/") }; if health["matcher"] == .null { health["matcher"] = .string("200") } }
        return health
    }
    static func listenerProtocol(_ protocolValue: String, listener: JSONValue) -> JSONValue {
        var listener = listener
        listener["protocol"] = .string(protocolValue)
        if !["HTTPS", "TLS"].contains(protocolValue) { listener["certificate_arn"] = .null; listener["ssl_policy"] = .null }
        return listener
    }
}
