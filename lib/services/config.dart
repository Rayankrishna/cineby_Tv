import 'package:flutter/material.dart';

// videasy.net is dead (NXDOMAIN). Catalog metadata now comes straight from
// TMDB v3 — same paths, different host + required api_key. Override the key
// at build time with --dart-define=TMDB_API_KEY=... to keep it out of source.
const String tmdbApiKey = String.fromEnvironment(
  'TMDB_API_KEY',
  defaultValue: '480d0e6b81cc6e4505b0da63dabecf14',
);
const String _tmdbBase = 'https://api.themoviedb.org/3';

// Playback embed defaults — 111Movies is current default (Videasy is dead).
// The full provider list lives in lib/services/stream_servers.dart; detail
// pages should prefer streamServers.first.buildUrl(...) over building URLs
// from these constants directly.
const String serverurl = 'https://111movies.net/movie/';
const String tvServerurl = 'https://111movies.net/tv/';

const String searchUrl =
    '$_tmdbBase/search/multi?api_key=$tmdbApiKey&language=en&page=1&query=';
const String homeUrl =
    '$_tmdbBase/trending/all/day?api_key=$tmdbApiKey&language=en';
const String topMoviesUrl =
    '$_tmdbBase/discover/movie?api_key=$tmdbApiKey&sort_by=popularity.desc&language=en&page=1';
const String topSeriesUrl =
    '$_tmdbBase/discover/tv?api_key=$tmdbApiKey&sort_by=popularity.desc&language=en&page=1';
const String topAnimeUrl =
    '$_tmdbBase/discover/tv?api_key=$tmdbApiKey&with_genres=16&with_origin_country=JP|CN&sort_by=popularity.desc&language=en&page=1';

// Genre rows on home. Same /discover/movie endpoint, one with_genres filter
// per row. TMDB genre ids — see https://developer.themoviedb.org/reference/genre-movie-list
String movieByGenreUrl(int genreId) =>
    '$_tmdbBase/discover/movie?api_key=$tmdbApiKey'
    '&with_genres=$genreId&sort_by=popularity.desc&language=en&page=1';

String tvByGenreUrl(int genreId) =>
    '$_tmdbBase/discover/tv?api_key=$tmdbApiKey'
    '&with_genres=$genreId&sort_by=popularity.desc&language=en&page=1';

const int tmdbGenreAction = 28;
const int tmdbGenreComedy = 35;
const int tmdbGenreDrama = 18;
const int tmdbGenreHorror = 27;
const int tmdbGenreSciFi = 878;
const int tmdbGenreRomance = 10749;

// Person filmography — every movie / TV show an actor has appeared in.
String personMovieCreditsUrl(int personId) =>
    '$_tmdbBase/person/$personId/movie_credits?api_key=$tmdbApiKey&language=en';
String personTvCreditsUrl(int personId) =>
    '$_tmdbBase/person/$personId/tv_credits?api_key=$tmdbApiKey&language=en';

const String movieDetailUrl = '$_tmdbBase/movie';
const String movieDetailParams =
    '?api_key=$tmdbApiKey&append_to_response=credits,external_ids,videos&language=en';

const String tvDetailUrl = '$_tmdbBase/tv';
const String tvDetailParams =
    '?api_key=$tmdbApiKey&append_to_response=credits,external_ids,videos&language=en';
const String tvSeasonUrl = '$_tmdbBase/tv';
const String tvSeasonParams = '?api_key=$tmdbApiKey&language=en';

// Avatar picker
const String popularPeopleUrl =
    '$_tmdbBase/person/popular?api_key=$tmdbApiKey&language=en&page=';

// Reelix backend
const String apiBaseUrl = 'https://cineby-main.vercel.app/api/v1';

// TMDB image bases
const String imgOriginal = 'https://image.tmdb.org/t/p/original';
const String imgW500 = 'https://image.tmdb.org/t/p/w500';
const String imgW300 = 'https://image.tmdb.org/t/p/w300';
const String imgW200 = 'https://image.tmdb.org/t/p/w200';
const String imgW185 = 'https://image.tmdb.org/t/p/w185';

// SharedPreferences keys
const String kPrefAccessToken = 'reelix.accessToken';
const String kPrefRefreshToken = 'reelix.refreshToken';
const String kPrefSelectedServer = 'reelix.selectedServer';
String kPrefAvatar(String userId) => 'reelix.avatar.$userId';

// UI palette
const Color kNetflixRed = Color(0xFFE50914);
const Color kDeepBlack = Color(0xFF0B0B10);
const Color kSurfaceGrey = Color(0xFF1A1A22);
const Color kSurfaceHi = Color(0xFF242430);
const Color kTextWhite = Colors.white;
const Color kTextGrey = Color(0xFFB3B3BB);
const Color kAccent = Color(0xFF60A5FA);
