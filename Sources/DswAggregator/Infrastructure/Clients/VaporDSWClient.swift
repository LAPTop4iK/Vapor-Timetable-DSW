//
//  VaporDSWClient.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

/// HTTP-клиент под harmonogramy.dsw.edu.pl
public final class VaporDSWClient: @unchecked Sendable, DSWClient {

    private let client: any Client
    public init(client: any Client) { self.client = client }

    // Константное окно — из реального браузерного запроса
    private let custWindowStateJSON =
        #"{"windowsState":"0:0:-1:0:0:0:-10000:-10000:1:0:0:0"}"#

    private func formURLEncode(_ dict: [String: String]) -> String {
        dict
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .sorted()
            .joined(separator: "&")
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func postForm(
        _ url: String,
        fields: [String: String]
    ) async throws -> String {
        let body = formURLEncode(fields)
        let res = try await client.post(URI(string: url)) { req in
            req.headers.replaceOrAdd(
                name: "User-Agent",
                value: "Mozilla/5.0 (DSW Aggregator)"
            )
            req.headers.replaceOrAdd(
                name: .contentType,
                value: "application/x-www-form-urlencoded; charset=UTF-8"
            )
            req.headers.replaceOrAdd(
                name: .accept,
                value: "text/html, */*; q=0.01"
            )
            req.body = .init(string: body)
        }

        guard res.status == .ok,
              let buf = res.body,
              let html = buf.getString(at: 0, length: buf.readableBytes)
        else {
            throw Abort(.badGateway,
                        reason: "POST \(url) -> \(res.status.code)")
        }
        return html
    }

    public func groupScheduleHTML(
        groupId: Int,
        from: String,
        to: String,
        interval: IntervalType = .semester
    ) async throws -> String {
        let url = "https://harmonogramy.dsw.edu.pl/Plany/PlanyGrupGridCustom/\(groupId)"
        let fields = [
            "DXCallbackName": "gridViewPlanyGrup",
            "gridViewPlanyGrup$custwindowState": custWindowStateJSON,
            "DXMVCEditorsValues": "{}",
            "parametry": "\(from);\(to);\(interval.rawValue);\(groupId)",
            "id": "\(groupId)"
        ]
        return try await postForm(url, fields: fields)
    }

    public func teacherScheduleHTML(
        teacherId: Int,
        from: String,
        to: String,
        interval: IntervalType = .semester
    ) async throws -> String {
        let url = "https://harmonogramy.dsw.edu.pl/Plany/PlanyProwadzacychGridCustom/\(teacherId)"
        let fields = [
            "DXCallbackName": "gridViewPlanyProwadzacych",
            "gridViewPlanyProwadzacych$custwindowState": custWindowStateJSON,
            "DXMVCEditorsValues": "{}",
            "parametry": "\(from);\(to);\(interval.rawValue);\(teacherId)",
            "id": "\(teacherId)"
        ]
        return try await postForm(url, fields: fields)
    }

    public func teacherInfoHTML(teacherId: Int) async throws -> String {
        let url = "https://harmonogramy.dsw.edu.pl/Plany/OpisProwadzacego/\(teacherId)"
        let resp = try await client.get(URI(string: url)) { req in
            req.headers.replaceOrAdd(
                name: "User-Agent",
                value: "Mozilla/5.0 (DSW Aggregator)"
            )
            req.headers.replaceOrAdd(
                name: .accept,
                value: "text/html, */*; q=0.01"
            )
        }
        guard resp.status == .ok,
              let buf = resp.body,
              let html = buf.getString(at: 0, length: buf.readableBytes)
        else {
            throw Abort(.badGateway,
                        reason: "GET \(url) -> \(resp.status.code)")
        }
        return html
    }
}
