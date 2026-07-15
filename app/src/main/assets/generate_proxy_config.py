import json
import urllib.parse
import sys
import os

def parse_vless(url, socks_port):
    try:
        parsed = urllib.parse.urlparse(url)
        uuid = parsed.username
        host = parsed.hostname
        port = parsed.port
        
        query = urllib.parse.parse_qs(parsed.query)
        
        def get_param(name, default=""):
            return query.get(name, [default])[0]
            
        security = get_param("security", "none")
        flow = get_param("flow", "")
        sni = get_param("sni", "")
        pbk = get_param("pbk", "")
        sid = get_param("sid", "")
        net_type = get_param("type", "tcp")
        path = get_param("path", "")
        service_name = get_param("serviceName", "")
        
        stream_settings = {
            "network": net_type
        }
        
        if security == "reality":
            stream_settings["security"] = "reality"
            stream_settings["realitySettings"] = {
                "fingerprint": "chrome",
                "serverName": sni,
                "publicKey": pbk,
                "shortId": sid
            }
        elif security == "tls":
            stream_settings["security"] = "tls"
            stream_settings["tlsSettings"] = {
                "serverName": sni,
                "allowInsecure": False
            }
        else:
            stream_settings["security"] = "none"
            
        if net_type == "ws":
            stream_settings["wsSettings"] = {
                "path": path,
                "headers": {
                    "Host": sni if sni else host
                }
            }
        elif net_type == "grpc":
            stream_settings["grpcSettings"] = {
                "serviceName": service_name,
                "multiMode": False
            }
            
        http_port = socks_port + 1
        
        config = {
            "log": { "loglevel": "warning" },
            "inbounds": [
                {
                    "port": socks_port,
                    "protocol": "socks",
                    "settings": { "auth": "noauth", "udp": True, "ip": "127.0.0.1" },
                    "sniffing": { "enabled": True, "destOverride": ["http", "tls"] }
                },
                {
                    "port": http_port,
                    "protocol": "http",
                    "settings": { "allowTransparent": False },
                    "sniffing": { "enabled": True, "destOverride": ["http", "tls"] }
                }
            ],
            "outbounds": [
                {
                    "protocol": "vless",
                    "settings": {
                        "vnext": [{
                            "address": host,
                            "port": port,
                            "users": [{
                                "id": uuid,
                                "encryption": "none",
                                "flow": flow
                            }]
                        }]
                    },
                    "streamSettings": stream_settings
                },
                {
                    "protocol": "freedom",
                    "tag": "direct"
                }
            ]
        }
        return config
    except Exception as e:
        print(f"Error parsing VLESS: {e}", file=sys.stderr)
        return None

def parse_hysteria2(url, socks_port):
    try:
        parsed = urllib.parse.urlparse(url)
        auth = parsed.username or parsed.password or ""
        if parsed.password:
            auth = f"{parsed.username}:{parsed.password}"
        elif parsed.username:
            auth = parsed.username
            
        host = parsed.hostname
        port = parsed.port or 443
        
        query = urllib.parse.parse_qs(parsed.query)
        def get_param(name, default=""):
            return query.get(name, [default])[0]
            
        insecure = get_param("insecure", "0") in ("1", "true")
        sni = get_param("sni", "")
        obfs_type = get_param("obfs", "")
        obfs_password = get_param("obfs-password", get_param("obfs_password", ""))
        
        http_port = socks_port + 1
        
        config = {
            "server": f"{host}:{port}",
            "auth": auth,
            "socks5": {
                "listen": f"127.0.0.1:{socks_port}"
            },
            "http": {
                "listen": f"127.0.0.1:{http_port}"
            },
            "tls": {
                "sni": sni if sni else host,
                "insecure": insecure
            }
        }
        
        if obfs_type:
            config["obfs"] = {
                "type": obfs_type,
                "password": obfs_password
            }
            
        return config
    except Exception as e:
        print(f"Error parsing Hysteria2: {e}", file=sys.stderr)
        return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate_proxy_config.py <link_file_or_url> [socks_port] [workspace_dir]")
        sys.exit(1)
        
    target = sys.argv[1]
    socks_port = int(sys.argv[2]) if len(sys.argv) > 2 else 10808
    workspace_dir = sys.argv[3] if len(sys.argv) > 3 else "/workspace"
    
    if os.path.isfile(target):
        with open(target, "r", encoding="utf-8") as f:
            url = f.read().strip()
    else:
        url = target
        
    if url.startswith("vless://"):
        config = parse_vless(url, socks_port)
        if config:
            # Save xray config
            with open(os.path.join(workspace_dir, "xray_config.json"), "w", encoding="utf-8") as f:
                json.dump(config, f, indent=2)
            # Write engine type
            with open(os.path.join(workspace_dir, "proxy_engine.txt"), "w", encoding="utf-8") as f:
                f.write("xray")
            print("Successfully generated Xray config.")
            sys.exit(0)
    elif url.startswith("hysteria2://") or url.startswith("hy2://"):
        config = parse_hysteria2(url, socks_port)
        if config:
            # Save hysteria config
            with open(os.path.join(workspace_dir, "hysteria_config.json"), "w", encoding="utf-8") as f:
                json.dump(config, f, indent=2)
            # Write engine type
            with open(os.path.join(workspace_dir, "proxy_engine.txt"), "w", encoding="utf-8") as f:
                f.write("hysteria")
            print("Successfully generated Hysteria2 config.")
            sys.exit(0)
    else:
        print(f"Unsupported protocol URL: {url}", file=sys.stderr)
        
    sys.exit(1)
