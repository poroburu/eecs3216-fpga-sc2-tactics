// Launch the installed Linux client, observe and step eight loops, then exit.
// Infrastructure check only: no UART exchange, tactical policy or game orders.
#include <sc2api/sc2_api.h>
#include <sc2api/sc2_control_interfaces.h>

#include <cstdint>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>

class SmokeAgent final : public sc2::Agent {
public:
    bool failed = false;

    void OnError(const std::vector<sc2::ClientError>& errors,
                 const std::vector<std::string>& messages) override {
        failed = true;
        for (const auto error : errors) {
            std::cerr << "SC2 client error " << static_cast<int>(error) << '\n';
        }
        for (const auto& message : messages) {
            std::cerr << "SC2 protocol error: " << message << '\n';
        }
    }
};

std::size_t CountVisibleSelf(const sc2::ObservationInterface* observation) {
    const auto* raw = observation->GetRawObservation();
    if (!raw || !raw->has_raw_data()) return 0;
    std::unordered_set<std::uint64_t> tags;
    for (const auto& unit : raw->raw_data().units()) {
        if (unit.alliance() != SC2APIProtocol::Self || unit.display_type() != SC2APIProtocol::Visible) continue;
        if (!unit.tag() || !tags.insert(unit.tag()).second ||
            !(unit.health() > 0) || unit.health() > unit.health_max()) {
            throw std::runtime_error("invalid raw friendly tag/health");
        }
    }
    return tags.size();
}

int main(int argc, char** argv) {
    if (argc < 3 || argc > 4) {
        std::cerr << "Usage: sc2_smoke /absolute/path/to/SC2_x64 /absolute/map.SC2Map [port-base=8168]\n";
        return 2;
    }
    try {
        int port = 8168;
        if (argc == 4) {
            std::size_t consumed = 0;
            port = std::stoi(argv[3], &consumed);
            if (consumed != std::string(argv[3]).size()) return 2;
        }
        if (port < 1024 || port > 65535) return 2;
        SmokeAgent agent;
        sc2::Coordinator coordinator;
        coordinator.SetProcessPath(argv[1]);
        coordinator.SetPortStart(port);
        coordinator.SetTimeoutMS(20000);
        coordinator.SetRealtime(false);
        coordinator.SetStepSize(1);
        coordinator.SetParticipants({
            sc2::CreateParticipant(sc2::Race::Terran, &agent),
            sc2::CreateComputer(sc2::Race::Zerg, sc2::Difficulty::VeryEasy)
        });
        coordinator.LaunchStarcraft();
        if (agent.failed || !agent.Control()->Ping()) return 1;
        const auto build = agent.Control()->Proto().GetBaseBuild();
        const auto data_version = agent.Control()->Proto().GetDataVersion();
        if (!coordinator.StartGame(argv[2]) || agent.failed) return 1;
        // Use raw protobuf facts: the pinned SDK's high-level converter aborts
        // on CloakedUnknown neutral units in this client, hiding valid friends.
        int startup_steps = 0;
        while (!CountVisibleSelf(agent.Observation()) && startup_steps < 64) {
            if (!coordinator.Update() || agent.failed) return 1;
            ++startup_steps;
        }
        const auto initial_loop = agent.Observation()->GetGameLoop();
        auto previous_loop = initial_loop;
        const auto self_units = CountVisibleSelf(agent.Observation());
        if (!self_units) {
            std::cerr << "No starting army after " << startup_steps
                      << " steps; loop=" << initial_loop
                      << " player=" << agent.Observation()->GetPlayerID()
                      << '\n';
            return 1;
        }
        for (int i = 0; i < 8; ++i) {
            if (!coordinator.Update() || agent.failed) return 1;
            const auto next_loop = agent.Observation()->GetGameLoop();
            if (next_loop != previous_loop + 1) {
                std::cerr << "Single-step loop mismatch: " << previous_loop << " -> " << next_loop << '\n';
                return 1;
            }
            if (!CountVisibleSelf(agent.Observation())) return 1;
            previous_loop = next_loop;
        }
        coordinator.LeaveGame();
        if (agent.failed) return 1;
        std::cout << "SC2_SMOKE_OK base_build=" << build
                  << " data_version=" << data_version
                  << " initial_loop=" << initial_loop
                  << " final_loop=" << previous_loop
                  << " startup_steps=" << startup_steps
                  << " steps=8 raw_self_units=" << self_units
                  << " sdk_self_units=" << agent.Observation()->GetUnits(sc2::Unit::Alliance::Self).size() << '\n';
        // Coordinator's destructor terminates only the client process it launched.
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "SC2 smoke failed: " << error.what() << '\n';
        return 1;
    }
}
