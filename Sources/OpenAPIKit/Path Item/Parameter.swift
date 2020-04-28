//
//  Parameter.swift
//  OpenAPI
//
//  Created by Mathew Polzin on 7/4/19.
//

import Foundation

extension OpenAPI.PathItem {
    /// OpenAPI Spec "Parameter Object"
    /// 
    /// See [OpenAPI Parameter Object](https://github.com/OAI/OpenAPI-Specification/blob/master/versions/3.0.3.md#parameter-object).
    public struct Parameter: Equatable {
        public var name: String

        /// OpenAPI Spec "in" property determines the `Context`.
        public var context: Context
        public var description: String?
        public var deprecated: Bool // default is false

        /// OpenAPI Spec "content" or "schema" properties.
        public var schemaOrContent: Either<Schema, OpenAPI.Content.Map>

        public var required: Bool { context.required }
        public var location: Context.Location { return context.location }

        /// An array of parameters that are `Either` `Parameters` or references to parameters.
        public typealias Array = [Either<JSONReference<Parameter>, Parameter>]

        public init(name: String,
                    context: Context,
                    schemaOrContent: Either<Schema, OpenAPI.Content.Map>,
                    description: String? = nil,
                    deprecated: Bool = false) {
            self.name = name
            self.context = context
            self.schemaOrContent = schemaOrContent
            self.description = description
            self.deprecated = deprecated
        }

        public init(name: String,
                    context: Context,
                    schema: Schema,
                    description: String? = nil,
                    deprecated: Bool = false) {
            self.name = name
            self.context = context
            self.schemaOrContent = .init(schema)
            self.description = description
            self.deprecated = deprecated
        }

        public init(name: String,
                    context: Context,
                    schema: JSONSchema,
                    description: String? = nil,
                    deprecated: Bool = false) {
            self.name = name
            self.context = context
            self.schemaOrContent = .init(Schema(schema, style: .default(for: context)))
            self.description = description
            self.deprecated = deprecated
        }

        public init(name: String,
                    context: Context,
                    schemaReference: JSONReference<JSONSchema>,
                    description: String? = nil,
                    deprecated: Bool = false) {
            self.name = name
            self.context = context
            self.schemaOrContent = .init(Schema(schemaReference: schemaReference, style: .default(for: context)))
            self.description = description
            self.deprecated = deprecated
        }

        public init(name: String,
                    context: Context,
                    content: OpenAPI.Content.Map,
                    description: String? = nil,
                    deprecated: Bool = false) {
            self.name = name
            self.context = context
            self.schemaOrContent = .init(content)
            self.description = description
            self.deprecated = deprecated
        }
    }
}

// MARK: `Either` convenience methods
// OpenAPI.PathItem.Array.Element =>
extension Either where A == JSONReference<OpenAPI.PathItem.Parameter>, B == OpenAPI.PathItem.Parameter {

    /// Construct a parameter.
    public static func parameter(
        name: String,
        context: OpenAPI.PathItem.Parameter.Context,
        schema: JSONSchema,
        description: String? = nil,
        deprecated: Bool = false
    ) -> Self {
        return .b(
            .init(
                name: name,
                context: context,
                schema: schema,
                description: description,
                deprecated: deprecated
            )
        )
    }

    /// Construct a parameter.
    public static func parameter(
        name: String,
        context: OpenAPI.PathItem.Parameter.Context,
        content: OpenAPI.Content.Map,
        description: String? = nil,
        deprecated: Bool = false
    ) -> Self {
        return .b(
            .init(
                name: name,
                context: context,
                content: content,
                description: description,
                deprecated: deprecated
            )
        )
    }
}

// MARK: - Codable
extension OpenAPI.PathItem.Parameter {
    private enum CodingKeys: String, CodingKey {
        case name
        case parameterLocation = "in"
        case description
        case required
        case deprecated
        case allowEmptyValue

        // the following are alternatives
        case content
        case schema
    }
}

extension OpenAPI.PathItem.Parameter: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)

        let required: Bool
        let location: Context.Location
        switch context {
        case .query(required: let req, allowEmptyValue: let allowEmptyValue):
            required = req
            location = .query

            if allowEmptyValue {
                try container.encode(allowEmptyValue, forKey: .allowEmptyValue)
            }
        case .header(required: let req):
            required = req
            location = .header
        case .path:
            required = true
            location = .path
        case .cookie(required: let req):
            required = req
            location = .cookie
        }
        try container.encode(location, forKey: .parameterLocation)

        if required {
            try container.encode(required, forKey: .required)
        }

        switch schemaOrContent {
        case .a(let schema):
            try schema.encode(to: encoder, for: context)
        case .b(let contentMap):
            try container.encode(contentMap, forKey: .content)
        }

        try description.encodeIfNotNil(to: &container, forKey: .description)

        if deprecated {
            try container.encode(deprecated, forKey: .deprecated)
        }
    }
}

extension OpenAPI.PathItem.Parameter: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let name = try container.decode(String.self, forKey: .name)
        self.name = name

        let required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        let location = try container.decode(Context.Location.self, forKey: .parameterLocation)

        switch location {
        case .query:
            let allowEmptyValue = try container.decodeIfPresent(Bool.self, forKey: .allowEmptyValue) ?? false
            context = .query(required: required, allowEmptyValue: allowEmptyValue)
        case .header:
            context = .header(required: required)
        case .path:
            if !required {
                throw InconsistencyError(
                    subjectName: name,
                    details: "positional path parameters must be explicitly set to required",
                    codingPath: decoder.codingPath
                )
            }
            context = .path
        case .cookie:
            context = .cookie(required: required)
        }

        let maybeContent = try container.decodeIfPresent(OpenAPI.Content.Map.self, forKey: .content)

        let maybeSchema: Schema?
        if container.contains(.schema) {
            maybeSchema = try Schema(from: decoder, for: context)
        } else {
            maybeSchema = nil
        }

        switch (maybeContent, maybeSchema) {
        case (let content?, nil):
            schemaOrContent = .init(content)
        case (nil, let schema?):
            schemaOrContent = .init(schema)
        default:
            throw InconsistencyError(
                subjectName: name,
                details: "A single path parameter must specify one but not both `content` and `schema`",
                codingPath: decoder.codingPath
            )
        }

        description = try container.decodeIfPresent(String.self, forKey: .description)

        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated) ?? false
    }
}
