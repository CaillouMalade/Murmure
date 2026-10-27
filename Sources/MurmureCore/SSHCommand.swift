import Foundation

public enum SSHCommand {
    public static func arguments(for endpoint: WorkerEndpoint) throws -> [String] {
        let aliasCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        let tokenCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:\\~-")
        guard !endpoint.host.isEmpty, endpoint.host.count <= 255, !endpoint.host.hasPrefix("-"),
              endpoint.host.unicodeScalars.allSatisfy(aliasCharacters.contains) else {
            throw MurmureError.message("Enter an SSH alias from ~/.ssh/config, using letters, numbers, dots, underscores or hyphens.")
        }
        for token in [endpoint.python, endpoint.script] {
            guard !token.isEmpty, !token.hasPrefix("-"), token.unicodeScalars.allSatisfy(tokenCharacters.contains) else {
                throw MurmureError.message("Remote Python and worker paths must not contain spaces or shell punctuation. Put the worker in a simple path such as C:/Murmure/worker/murmure_worker.py.")
            }
        }
        return ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", "--", endpoint.host,
                "\(endpoint.python) -u \(endpoint.script) rpc"]
    }
}
