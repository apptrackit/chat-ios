//
//  APIClient.swift
//  Inviso
//
//  Handles all REST API communication with the backend server.
//

import Foundation

final class APIClient {
    private var apiBase: URL { URL(string: "https://\(ServerConfig.shared.host)")! }

    // MARK: - Room Management

    func createRoom(joinCode: String, expiration: Date, clientID: String) async throws {
        let expISO = ISO8601DateFormatter().string(from: expiration)
        var request = URLRequest(url: apiBase.appendingPathComponent("/api/rooms"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["joinid": joinCode, "exp": expISO, "client1": clientID]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    func acceptJoinCode(_ code: String, clientID: String) async -> String? {
        var request = URLRequest(url: apiBase.appendingPathComponent("/api/rooms/accept"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["joinid": code, "client2": clientID])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let roomID = json["roomid"] as? String {
                return roomID
            }

            if httpResponse.statusCode == 404 || httpResponse.statusCode == 409 {
                return nil
            }
        } catch {
            print("acceptJoinCode error: \(error)")
        }
        return nil
    }

    func checkPendingRoom(joinCode: String, clientID: String) async -> String? {
        var request = URLRequest(url: apiBase.appendingPathComponent("/api/rooms/check"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["joinid": joinCode, "client1": clientID])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let roomID = json["roomid"] as? String {
                return roomID
            }

            if httpResponse.statusCode == 204 || httpResponse.statusCode == 404 {
                return nil
            }
        } catch {
            print("checkPendingRoom error: \(error)")
        }
        return nil
    }

    func getRoom(roomID: String) async -> (client1: String, client2: String)? {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("/api/rooms"), resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "roomid", value: roomID)]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let client1 = json["client1"] as? String,
               let client2 = json["client2"] as? String {
                return (client1, client2)
            }
        } catch {
            print("getRoom error: \(error)")
        }
        return nil
    }

    func deleteRoom(roomID: String) async {
        var request = URLRequest(url: apiBase.appendingPathComponent("/api/rooms"))
        request.httpMethod = "DELETE"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["roomid": roomID])

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            print("deleteRoom error: \(error)")
        }
    }

    // MARK: - Room Status Check

    enum RoomStatus {
        case exists
        case notFound
        case unreachable
    }

    func getRoomStatus(_ roomID: String) async -> RoomStatus {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("/api/rooms"), resolvingAgainstBaseURL: false) else { return .unreachable }
        components.queryItems = [URLQueryItem(name: "roomid", value: roomID)]
        guard let url = components.url else { return .unreachable }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return .unreachable }

            if httpResponse.statusCode == 200 {
                // Basic validation that payload has expected keys
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["client1"] != nil {
                    return .exists
                } else {
                    return .exists // Consider 200 as exists even if parsing partial
                }
            } else if httpResponse.statusCode == 404 {
                return .notFound
            } else {
                return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}
