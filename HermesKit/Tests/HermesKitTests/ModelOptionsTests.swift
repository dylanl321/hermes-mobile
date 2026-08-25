import Foundation
import Testing

@testable import HermesKit

struct ModelOptionsTests {
  @Test func decodesProvidersModelsAndCapabilities() throws {
    let json = #"""
    {
      "model": "claude-opus-4-8",
      "provider": "anthropic",
      "providers": [
        {
          "name": "Anthropic", "slug": "anthropic", "authenticated": true,
          "models": ["claude-opus-4-8", "claude-haiku-4-5"],
          "capabilities": {
            "claude-opus-4-8": {"fast": false, "reasoning": true},
            "claude-haiku-4-5": {"fast": true, "reasoning": false}
          }
        },
        { "name": "OpenAI", "slug": "openai", "models": [], "authenticated": false, "warning": "paste OPENAI_API_KEY to activate" }
      ]
    }
    """#
    let options = try JSONDecoder().decode(ModelOptions.self, from: Data(json.utf8))

    #expect(options.currentModel == "claude-opus-4-8")
    #expect(options.providers.count == 2)
    // Configured providers first, then unconfigured (with a hint); both kept.
    #expect(options.orderedProviders.map(\.name) == ["Anthropic", "OpenAI"])
    #expect(options.orderedProviders.map(\.isConfigured) == [true, false])
    #expect(options.providers.first(where: { $0.name == "OpenAI" })?.warning == "paste OPENAI_API_KEY to activate")
  }

  @Test func orderedProvidersPutsConfiguredFirstAndDropsEmptyNoHint() {
    let options = ModelOptions(providers: [
      .init(name: "Unconfigured", slug: "u", models: [], authenticated: false, warning: "configure me"),
      .init(name: "Configured", slug: "c", models: ["m"], authenticated: true),
      .init(name: "Empty", slug: "e", models: [], authenticated: false), // no models, no hint → dropped
    ])
    #expect(options.orderedProviders.map(\.name) == ["Configured", "Unconfigured"])
  }

  @Test func supportsReasoningReflectsPerModelCapability() {
    let options = ModelOptions(
      providers: [.init(
        name: "Anthropic", slug: "anthropic",
        models: ["opus", "haiku"], authenticated: true,
        capabilities: ["opus": .init(reasoning: true), "haiku": .init(reasoning: false)]
      )],
      currentModel: "opus"
    )
    #expect(options.supportsReasoning("opus") == true)
    #expect(options.supportsReasoning("haiku") == false)
    // Unknown model / nil → default true (don't hide the control on unknowns).
    #expect(options.supportsReasoning("mystery") == true)
    #expect(options.supportsReasoning(nil) == true)
  }

  @Test func reasoningLadderIsTheFullUpstreamScale() {
    #expect(ModelOptions.reasoningEfforts == [
      "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra",
    ])
    #expect(ModelOptions.reasoningEfforts.first == "none")
    #expect(ModelOptions.reasoningEfforts.last == "ultra")
  }

  @Test func offeredEffortsReturnsFullLadderWhenExtendedSupported() {
    #expect(ModelOptions.offeredEfforts(extendedSupported: true) == ModelOptions.reasoningEfforts)
  }

  @Test func offeredEffortsDropsExactlyMaxAndUltraWhenLatched() {
    let offered = ModelOptions.offeredEfforts(extendedSupported: false)
    #expect(offered == ["none", "minimal", "low", "medium", "high", "xhigh"])
    // Only the extended levels are removed; the rest keeps ladder order.
    #expect(Set(ModelOptions.reasoningEfforts).subtracting(offered) == ModelOptions.extendedReasoningEfforts)
    #expect(offered == ModelOptions.reasoningEfforts.filter { offered.contains($0) })
  }

  @Test func extendedEffortsAreASubsetOfTheLadder() {
    #expect(ModelOptions.extendedReasoningEfforts.isSubset(of: Set(ModelOptions.reasoningEfforts)))
    #expect(ModelOptions.extendedReasoningEfforts == ["max", "ultra"])
  }
}
