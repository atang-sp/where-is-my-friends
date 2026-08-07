import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import { relativeAge } from "discourse/lib/formatter";
import { clipboardCopy } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";
import LocationModeDialog from "../components/location-mode-dialog";
import VirtualLocationPicker from "../components/virtual-location-picker";
import { createClientTelemetry } from "./client-telemetry";
import { normalizeCityClient } from "./where-is-my-friends-city";
import { getCurrentPositionAsync } from "./where-is-my-friends-geolocation";

export default class LocationDiscoveryWorkflow {
  @tracked city;
  @tracked region;
  @tracked location;
  @tracked discoveryState;
  @tracked users = [];
  @tracked cityGroups = [];
  @tracked loading = false;
  @tracked error = null;
  @tracked gpsFallback = false;
  @tracked memberFilter = "";
  @tracked showRegion;
  @tracked inviteFeedback = null;
  @tracked notifyCity;
  @tracked notifyNearby;
  @tracked nearbyCityCount = 0;
  @tracked nearbyCityCountSuppressed = false;
  @tracked resultsLimited = false;
  @tracked expandedRadius = false;
  @tracked originalRadiusKm = null;
  @tracked expandedRadiusKm = null;
  @tracked autoCity = null;
  @tracked activeFilters = {};
  @tracked networkPreview = null;
  @tracked previewLoading = false;
  @tracked selectedPreviewRadius = null;

  constructor({
    model,
    currentUser,
    modal,
    router,
    siteSettings,
    transport = ajax,
    telemetry = createClientTelemetry(),
    geolocate = getCurrentPositionAsync,
    copyToClipboard = clipboardCopy,
    currentLocation = window.location,
    schedule = next,
  }) {
    this.model = model;
    this.currentUser = currentUser;
    this.modal = modal;
    this.router = router;
    this.siteSettings = siteSettings;
    this.transport = transport;
    this.telemetry = telemetry;
    this.geolocate = geolocate;
    this.copyToClipboard = copyToClipboard;
    this.currentLocation = currentLocation;
    this.schedule = schedule;

    const autoCity =
      this.router?.currentRoute?.queryParams?.auto_city ??
      new URLSearchParams(this.currentLocation.search).get("auto_city");
    this.city =
      this.model.location?.city ??
      autoCity ??
      this.model.profile_location ??
      "";
    this.autoCity = autoCity && !this.model.location ? autoCity : null;
    this.region = this.model.location?.region ?? "";
    this.showRegion = Boolean(this.region);
    this.location = this.model.location;
    this.discoveryState = this.model.state;
    this.notifyCity =
      this.currentUser?.user_option?.where_is_my_friends_notify_city ?? true;
    this.notifyNearby =
      this.currentUser?.user_option?.where_is_my_friends_notify_nearby ?? true;

    this.intents = Object.freeze({
      initialize: this.initialize,
      setup: Object.freeze({
        change: this.changeSetup,
        previewCity: this.previewCity,
        save: this.saveCity,
        trackLocalTopic: this.trackLocalTopicCompose,
      }),
      results: Object.freeze({
        copyInvite: this.copyInvite,
        changeFilter: this.selectFilter,
        changeRadius: this.selectDiscoveryRadius,
        connect: this.trackConnection,
        manageLocation: this.manageLocation,
        openLocalTopic: this.trackLocalTopicOpen,
        setMemberFilter: this.setMemberFilter,
        toggleCityNotifications: this.toggleNotifyCity,
      }),
    });
  }

  get view() {
    return {
      mode: this.isSetup ? "setup" : "results",
      discoveryState: this.discoveryState,
      error: this.error,
      setup: this.isSetup ? this.setupState : null,
      results: this.isSetup ? null : this.resultsState,
    };
  }

  get setupState() {
    return {
      proof: this.participantProof,
      directory: {
        visible: this.hasCityDirectory,
        value: this.cityDirectory,
        options: this.cityOptions,
      },
      form: {
        autoCity: this.autoCity,
        city: this.city,
        cityPreview: this.cityPreview,
        normalizationHint: this.cityNormalizationHint,
        region: this.region,
        showRegion: this.showRegion,
      },
      preview: {
        value: this.networkPreview,
        loading: this.previewLoading,
        radiusButtons: this.previewRadiusButtons,
        joinLabel: this.previewJoinLabel,
      },
      notifications: {
        city: this.notifyCity,
        nearby: this.notifyNearby,
      },
      saving: this.loading,
    };
  }

  get resultsState() {
    return {
      location: {
        value: this.location,
        radiusButtons: this.discoveryRadiusButtons,
        gpsFallback: this.gpsFallback,
        virtualEnabled: this.model.settings?.virtual_location_enabled ?? false,
      },
      status: {
        loading: this.loading,
        hasUsers: this.hasUsers,
        isEmpty: this.isEmpty,
        isLimited: this.isLimited,
        resultsLimited: this.resultsLimited,
        expandedRadius: this.expandedRadius,
        originalRadiusKm: this.originalRadiusKm,
        expandedRadiusKm: this.expandedRadiusKm,
        summary: this.resultsSummary,
      },
      discovery: {
        chatEnabled: this.chatEnabled,
        cityGroups: this.displayCityGroups,
        filterGroups: this.filterGroups,
        hasActiveFilters: this.hasActiveFilters,
        hasFilterableFields: this.hasFilterableFields,
        memberFilter: this.memberFilter,
        showMemberFilter: this.showMemberFilter,
      },
      empty: {
        inviteFeedback: this.inviteFeedback,
        nearbyCityCount: this.nearbyCityCount,
        nearbyCityCountSuppressed: this.nearbyCityCountSuppressed,
        notifyCity: this.notifyCity,
        participantProof: this.participantProof,
      },
      localTopic: {
        actionUrl: this.localTopicActionUrl,
        city: this.location.city,
      },
    };
  }

  get isSetup() {
    return this.discoveryState === "setup";
  }

  get isEmpty() {
    return this.discoveryState === "empty";
  }

  get isLimited() {
    return this.discoveryState === "limited";
  }

  get availableUsers() {
    const username =
      this.currentUser?.username ?? this.model.current_user?.username;
    return this.users.filter((user) => user.username !== username);
  }

  get hasUsers() {
    return this.availableUsers.length > 0;
  }

  get showMemberFilter() {
    return this.availableUsers.length >= 10;
  }

  get chatEnabled() {
    return this.siteSettings.chat_enabled && this.currentUser?.has_chat_enabled;
  }

  get visibleUsers() {
    const bandOrder = {
      same_city: 0,
      under_5: 1,
      nearby: 2,
      "5_to_20": 3,
      moderate: 4,
      over_20: 5,
      far: 6,
    };
    const query = this.memberFilter.trim().toLocaleLowerCase();
    const users = query
      ? this.availableUsers.filter((user) =>
          [user.name, user.username].some((value) =>
            value?.toLocaleLowerCase().includes(query)
          )
        )
      : this.availableUsers;

    const useChat = this.chatEnabled;
    const fields = this.filterableFields;
    return [...users]
      .sort(
        (a, b) =>
          (bandOrder[a.distance_band ?? "same_city"] ?? 99) -
          (bandOrder[b.distance_band ?? "same_city"] ?? 99)
      )
      .map((user) => {
        const lastActiveLabel = user.last_seen_at
          ? relativeAge(new Date(user.last_seen_at), { format: "tiny" })
          : null;
        let activityLabel = null;
        if (user.online) {
          activityLabel = i18n("where_is_my_friends.online_now");
        } else if (lastActiveLabel) {
          activityLabel = i18n("where_is_my_friends.seen_recently", {
            time: lastActiveLabel,
          });
        }

        return {
          ...user,
          distance_label:
            (user.distance_band ?? "same_city") === "same_city"
              ? null
              : i18n(
                  `where_is_my_friends.distance_bands.${user.distance_band}`
                ),
          action_url: useChat
            ? `/chat/new-message?recipients=${encodeURIComponent(user.username)}`
            : user.message_url,
          activity_label: activityLabel,
          custom_field_label: fields
            .map((field) => user.custom_fields?.[field.name])
            .filter(Boolean)
            .join(" / "),
          inactive: user.activity_status === "inactive",
        };
      });
  }

  get displayCityGroups() {
    const visibleUsers = new Map(
      this.visibleUsers.map((user) => [user.username, user])
    );
    const groups = this.cityGroups.length
      ? this.cityGroups
      : [
          {
            city: this.location?.city,
            city_key: this.location?.city,
            distance_band: "same_city",
            approximate_distance_km: null,
            recent_active_count: this.visibleUsers.filter(
              (user) => !user.inactive
            ).length,
            joined_count: this.visibleUsers.length,
            users: this.users,
            synthetic: true,
          },
        ];

    return groups
      .map((group) => {
        const users = group.users
          .map((user) => visibleUsers.get(user.username))
          .filter(Boolean);
        const sameCity = group.distance_band === "same_city";
        return {
          ...group,
          users,
          heading_label: sameCity
            ? i18n("where_is_my_friends.city_group_same", {
                city: group.city,
              })
            : i18n("where_is_my_friends.city_group_nearby", {
                city: group.city,
                distance: group.approximate_distance_km,
              }),
          counts_label: i18n("where_is_my_friends.city_group_counts", {
            active: group.recent_active_count,
            joined: group.joined_count,
          }),
        };
      })
      .filter((group) => group.users.length > 0);
  }

  get resultsSummary() {
    const count = this.availableUsers.length;
    return i18n(
      count === 1
        ? "where_is_my_friends.results_count_one"
        : "where_is_my_friends.results_count_other",
      {
        city: this.location.city,
        count,
        radius: this.expandedRadius
          ? this.expandedRadiusKm
          : this.discoveryRadiusKm,
      }
    );
  }

  get discoveryRadiusKm() {
    return (
      this.location?.discovery_radius_km ??
      this.model.settings?.default_discovery_radius_km ??
      100
    );
  }

  get discoveryRadiusOptions() {
    return this.model.settings?.discovery_radius_options_km ?? [50, 100, 200];
  }

  get discoveryRadiusButtons() {
    return this.discoveryRadiusOptions.map((radius) => ({
      radius,
      selected: radius === this.discoveryRadiusKm,
      label: i18n("where_is_my_friends.discovery_radius_option", { radius }),
    }));
  }

  get filterableFields() {
    return this.model.filterable_fields ?? [];
  }

  get hasFilterableFields() {
    return this.filterableFields.length > 0;
  }

  get hasActiveFilters() {
    return Object.keys(this.activeFilters).length > 0;
  }

  get filterGroups() {
    return this.filterableFields.map((field) => ({
      ...field,
      buttons: [
        {
          value: null,
          label: i18n("where_is_my_friends.filter_all"),
          selected: !this.activeFilters[field.key],
        },
        ...field.options.map((option) => ({
          value: option,
          label: option,
          selected: this.activeFilters[field.key] === option,
        })),
      ],
    }));
  }

  get participantProof() {
    const participants = this.model.active_participants;
    if (!participants || participants.suppressed) {
      return i18n("where_is_my_friends.participant_proof_generic");
    }

    if (participants.city_count) {
      return i18n("where_is_my_friends.global_stats", {
        count: participants.count,
        city_count: participants.city_count,
      });
    }

    return i18n("where_is_my_friends.participant_proof_count", {
      count: participants.count,
    });
  }

  get cityDirectory() {
    return this.model.city_directory ?? null;
  }

  get hasCityDirectory() {
    return Boolean(
      this.cityDirectory?.active?.length || this.cityDirectory?.growing?.length
    );
  }

  get cityOptions() {
    return this.model.city_catalogue ?? this.model.city_suggestions ?? [];
  }

  get previewRadiusButtons() {
    return (this.networkPreview?.radius_options ?? []).map((option) => ({
      ...option,
      selected: option.radius_km === this.selectedPreviewRadius,
      label: option.counts_suppressed
        ? i18n("where_is_my_friends.preview_radius_counts_suppressed", {
            radius: option.radius_km,
          })
        : i18n("where_is_my_friends.preview_radius_summary", {
            radius: option.radius_km,
            active: option.recent_active_count,
            joined: option.joined_count,
          }),
    }));
  }

  get previewJoinLabel() {
    return i18n("where_is_my_friends.join_preview_city", {
      city: this.networkPreview?.city?.city ?? this.city,
    });
  }

  get localTopicActionUrl() {
    return `/search?q=${encodeURIComponent(this.location?.city ?? "")}`;
  }

  get cityPreview() {
    const input = this.city.trim().toLowerCase();
    if (!input) {
      return null;
    }

    const normalizedInput = normalizeCityClient(input);
    const match = this.model.city_suggestions?.find(
      (suggestion) =>
        suggestion.city.toLowerCase() === input ||
        suggestion.city_key === normalizedInput
    );

    if (!Number.isFinite(match?.count) || match.count < 1) {
      return null;
    }

    const threshold = this.model.settings?.aggregate_privacy_threshold ?? 3;
    if (match.count < threshold) {
      return null;
    }

    return i18n("where_is_my_friends.city_member_count", {
      count: match.count,
      city: match.city,
    });
  }

  get cityNormalizationHint() {
    const raw = this.city.trim();
    if (!raw) {
      return null;
    }

    const normalized = normalizeCityClient(raw);
    const comparable = raw.replace(/\s+/g, " ").toLowerCase();
    if (normalized === comparable) {
      return null;
    }

    return i18n("where_is_my_friends.city_will_match_as", { normalized });
  }

  @action
  async initialize() {
    void this.telemetry.record("page_view");
    void this.telemetry.record("directory_viewed");
    const notificationSource = new URLSearchParams(
      this.currentLocation.search
    ).get("notification");
    if (notificationSource) {
      void this.telemetry.record("notification_opened");
    }
    if (this.discoveryState === "ready") {
      await this.loadResults();
    }
  }

  @action
  changeSetup(patch) {
    if (Object.hasOwn(patch, "city")) {
      this.city = patch.city;
      this.networkPreview = null;
      this.selectedPreviewRadius = null;
    }
    if (Object.hasOwn(patch, "region")) {
      this.region = patch.region;
    }
    if (Object.hasOwn(patch, "showRegion")) {
      this.showRegion = patch.showRegion;
    }
    if (Object.hasOwn(patch, "notifyCity")) {
      this.notifyCity = patch.notifyCity;
    }
    if (Object.hasOwn(patch, "notifyNearby")) {
      this.notifyNearby = patch.notifyNearby;
    }
    if (Object.hasOwn(patch, "previewRadius")) {
      this.selectedPreviewRadius = patch.previewRadius;
    }
  }

  @action
  previewCity(city = this.city) {
    if (city !== this.city) {
      this.city = city;
    }
    return this.loadCityPreview(city);
  }

  async loadCityPreview(city) {
    const requestedCity = city.trim();
    if (!requestedCity || this.previewLoading) {
      return;
    }

    this.previewLoading = true;
    this.error = null;
    try {
      const response = await this.transport(
        "/where-is-my-friends/cities/preview.json",
        { data: { city: requestedCity } }
      );
      this.networkPreview = response;
      this.city = response.city?.city ?? requestedCity;
      this.selectedPreviewRadius =
        response.recommended_radius_km ??
        this.model.settings?.default_discovery_radius_km ??
        100;
      void this.telemetry.record("city_previewed");
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.previewLoading = false;
    }
  }

  @action
  setMemberFilter(value) {
    this.memberFilter = value;
  }

  @action
  async selectFilter(fieldKey, value) {
    const newFilters = { ...this.activeFilters };
    if (value === null) {
      delete newFilters[fieldKey];
    } else {
      newFilters[fieldKey] = value;
    }
    this.activeFilters = newFilters;
    await this.loadResults();
  }

  @action
  async saveCity() {
    if (!this.city.trim() || this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    void this.telemetry.record("setup_started", { locationMode: "city" });

    try {
      const response = await this.transport(
        "/where-is-my-friends/locations.json",
        {
          type: "POST",
          data: {
            city: this.city.trim(),
            region: this.region.trim(),
            discovery_mode: "city",
            discovery_radius_km:
              this.selectedPreviewRadius ?? this.discoveryRadiusKm,
            notify_city: this.notifyCity,
            notify_nearby: this.notifyNearby,
          },
        }
      );
      this.location = response.location;
      this.discoveryState = response.state;
      this.networkPreview = null;
      void this.telemetry.record("radius_confirmed", { locationMode: "city" });
      void this.telemetry.record("location_saved", { locationMode: "city" });
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  async loadResults() {
    this.loading = true;
    this.error = null;

    try {
      const data = {};
      for (const [key, value] of Object.entries(this.activeFilters)) {
        data[`filters[${key}]`] = value;
      }
      const response = await this.transport(
        "/where-is-my-friends/locations/nearby.json",
        { data }
      );
      this.users = response.users ?? [];
      this.cityGroups = response.city_groups ?? [];
      this.nearbyCityCount = response.nearby_city_count ?? 0;
      this.nearbyCityCountSuppressed =
        response.nearby_city_count_suppressed ?? false;
      this.resultsLimited = response.results_limited ?? false;
      this.expandedRadius = response.expanded_radius ?? false;
      this.originalRadiusKm = response.original_radius_km ?? null;
      this.expandedRadiusKm = response.expanded_radius_km ?? null;
      this.discoveryState =
        this.availableUsers.length > 0
          ? "ready"
          : this.resultsLimited
            ? "limited"
            : "empty";
      void this.telemetry.record("results_viewed", {
        locationMode: this.location?.discovery_mode ?? "city",
        resultCount: this.availableUsers.length,
      });
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async selectDiscoveryRadius(radiusKm) {
    if (!this.location || this.loading || radiusKm === this.discoveryRadiusKm) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await this.transport(
        "/where-is-my-friends/locations.json",
        {
          type: "POST",
          data: {
            city: this.location.city,
            region: this.location.region ?? "",
            discovery_mode: this.location.discovery_mode ?? "city",
            discovery_radius_km: radiusKm,
          },
        }
      );
      this.location = response.location;
      this.discoveryState = response.state;
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  openAdvancedLocation() {
    this.gpsFallback = false;
    this.modal.show(LocationModeDialog, {
      model: {
        onGps: () => this.upgradeWithGps(),
        onMap: () => this.schedule(() => this.openMapPicker()),
      },
    });
  }

  @action
  manageLocation(command) {
    return {
      advanced: this.openAdvancedLocation,
      edit: this.editLocation,
      remove: this.removeLocation,
    }[command]?.();
  }

  @action
  openMapPicker() {
    this.modal.show(VirtualLocationPicker, {
      model: {
        settings: this.model.settings,
        onConfirm: (coordinates) => this.savePrecise("map", coordinates),
      },
    });
  }

  async upgradeWithGps() {
    this.loading = true;
    this.error = null;
    try {
      const position = await this.geolocate();
      await this.savePrecise("gps", {
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        location_accuracy: position.coords.accuracy,
      });
    } catch {
      this.gpsFallback = true;
      this.loading = false;
    }
  }

  async savePrecise(discoveryMode, coordinates) {
    this.loading = true;
    this.error = null;
    try {
      const response = await this.transport(
        "/where-is-my-friends/locations.json",
        {
          type: "POST",
          data: {
            city: this.location.city,
            region: this.location.region ?? "",
            discovery_mode: discoveryMode,
            ...coordinates,
          },
        }
      );
      this.location = response.location;
      this.discoveryState = response.state;
      void this.telemetry.record("location_saved", {
        locationMode: discoveryMode,
      });
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  editLocation() {
    this.discoveryState = "setup";
    this.showRegion = Boolean(this.region);
    this.users = [];
    this.cityGroups = [];
    this.memberFilter = "";
    this.activeFilters = {};
    this.gpsFallback = false;
  }

  @action
  async removeLocation() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      await this.transport("/where-is-my-friends/locations.json", {
        type: "DELETE",
      });
      void this.telemetry.record("location_removed", {
        locationMode: this.location?.discovery_mode ?? "city",
      });
      this.location = null;
      this.users = [];
      this.cityGroups = [];
      this.discoveryState = "setup";
      this.memberFilter = "";
      this.activeFilters = {};
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  trackConnection(eventName) {
    void this.telemetry.record(eventName, {
      locationMode: this.location?.discovery_mode ?? "city",
    });
  }

  @action
  trackLocalTopicOpen() {
    void this.telemetry.record("local_topic_opened", {
      locationMode: this.location?.discovery_mode ?? "city",
    });
  }

  @action
  trackLocalTopicCompose() {
    void this.telemetry.record("local_topic_interacted", {
      locationMode: this.location?.discovery_mode ?? "city",
    });
  }

  @action
  async copyInvite() {
    try {
      const url = new URL("/where-is-my-friends", this.currentLocation.href);
      if (this.location?.city) {
        url.searchParams.set("auto_city", this.location.city);
      }
      await this.copyToClipboard(url.href);
      this.inviteFeedback = i18n("where_is_my_friends.invite_copied");
    } catch {
      this.inviteFeedback = i18n("where_is_my_friends.invite_copy_failed");
    }
  }

  @action
  async toggleNotifyCity() {
    this.notifyCity = !this.notifyCity;
    try {
      await this.transport(`/u/${this.currentUser.username}.json`, {
        type: "PUT",
        data: {
          where_is_my_friends_notify_city: this.notifyCity,
        },
      });
    } catch {
      this.notifyCity = !this.notifyCity;
    }
  }

  errorMessage(error) {
    const response = error?.jqXHR?.responseJSON ?? error?.responseJSON;
    return response?.errors?.[0] ?? i18n("where_is_my_friends.generic_error");
  }
}
