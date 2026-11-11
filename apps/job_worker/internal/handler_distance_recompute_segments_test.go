package internal

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// segmentedRun is one of the shared vectors' segmentedRuns (spec v1.8): a
// watch run over several estimator segments, the totals its recorder saves,
// and what the worker's replay of its marked track must give.
type segmentedRun struct {
	Name     string `json:"name"`
	Segments []struct {
		Events []struct {
			Type     string   `json:"type"`
			T        float64  `json:"t"`
			Lat      *float64 `json:"lat"`
			Lng      *float64 `json:"lng"`
			Acc      *float64 `json:"acc"`
			Speed    *float64 `json:"speed"`
			SpeedAcc *float64 `json:"speedAcc"`
			Bearing  *float64 `json:"bearing"`
		} `json:"events"`
	} `json:"segments"`
	Expected struct {
		DistanceM      float64 `json:"distanceM"`
		StepDistanceM  float64 `json:"stepDistanceM"`
		StepOverChordM float64 `json:"stepOverChordM"`
	} `json:"expected"`
	Recompute struct {
		ReplayedM         float64 `json:"replayedM"`
		GapM              float64 `json:"gapM"`
		DistanceM         float64 `json:"distanceM"`
		UnmarkedReplayedM float64 `json:"unmarkedReplayedM"`
		UnmarkedGapM      float64 `json:"unmarkedGapM"`
		UnmarkedDistanceM float64 `json:"unmarkedDistanceM"`
	} `json:"recompute"`
}

func segmentedRuns(t *testing.T) []segmentedRun {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "fixtures", "gps_distance_vectors.json"))
	if err != nil {
		t.Fatal(err)
	}
	var vf struct {
		SegmentedRuns []segmentedRun `json:"segmentedRuns"`
	}
	if err := json.Unmarshal(raw, &vf); err != nil {
		t.Fatal(err)
	}
	if len(vf.SegmentedRuns) == 0 {
		t.Fatal("the shared vectors carry no segmentedRuns")
	}
	return vf.SegmentedRuns
}

// storedTrack is the run's track as a v1.8 watch stores it: every fix, in
// order, each later segment's first one marked segmentStart when marked.
// first[k] is the index of segment k's first fix.
func (s segmentedRun) storedTrack(marked bool) (track []RecordedTrackPoint, first []int) {
	t0 := time.Date(2026, 11, 10, 7, 0, 0, 0, time.UTC)
	for k, seg := range s.Segments {
		first = append(first, len(track))
		for _, e := range seg.Events {
			if e.Type != "fix" {
				continue
			}
			ts := t0.Add(time.Duration(math.Round(e.T*1000)) * time.Millisecond)
			track = append(track, RecordedTrackPoint{
				Lat: e.Lat, Lng: e.Lng, Timestamp: &ts,
				AccuracyM: e.Acc, SpeedMps: e.Speed, SpeedAccuracyMps: e.SpeedAcc, BearingDeg: e.Bearing,
				SegmentStart: marked && k > 0 && len(track) == first[k],
			})
		}
	}
	return track, first
}

// A watch run's marked track recomputes to the recorder's figure: a Wear OS
// handover inside a gap (238.00 m), a pause inside a gap (242.00 m) and a
// runner who walks while paused (480.00 m). The replay of the same track as
// one stream, every track before v1.8, is pinned beside it.
//
// A v1.8 track that lost its marks on the way to storage replays as one
// segment while distance_segments says two, so the key, which banks the steps
// each close committed past its segment's last fix, gives way to the run-total
// rule: 235.52 + max(47.52, 50) - 47.52 = 238.00 m and 235.52 + max(75.52, 82)
// - 75.52 = 242.00 m (reference.py recompute_distance), where the key over the
// one-stream replay would read 285.52 m and 317.52 m. The walk while paused
// reads 575.52 m either way: its key is 0, and no gap rule can take back the
// chord the one-stream replay credits across the pause.
func TestDistanceRecompute_SegmentedWatchRunsMatchTheRecorder(t *testing.T) {
	want := map[string]float64{
		"segments_handover_open_gap": 238.00,
		"segments_pause_in_gap":      242.00,
		"segments_pause_moved":       480.00,
	}
	wantUnmarked := map[string]float64{
		"segments_handover_open_gap": 238.00,
		"segments_pause_in_gap":      242.00,
		"segments_pause_moved":       575.52,
	}
	for _, s := range segmentedRuns(t) {
		t.Run(s.Name, func(t *testing.T) {
			if w, ok := want[s.Name]; ok && math.Abs(s.Expected.DistanceM-w) > 0.005 {
				t.Fatalf("vector's recorder figure %.3f, want %.2f", s.Expected.DistanceM, w)
			}
			if w, ok := wantUnmarked[s.Name]; ok && math.Abs(s.Recompute.UnmarkedDistanceM-w) > 0.005 {
				t.Fatalf("vector's unmarked recompute %.3f, want %.2f", s.Recompute.UnmarkedDistanceM, w)
			}
			track, first := s.storedTrack(true)
			replay := replayRecordedTrack(track, 10)
			if replay.Segments != len(s.Segments) {
				t.Errorf("replayed %d segments, want %d", replay.Segments, len(s.Segments))
			}
			if math.Abs(replay.SmoothedM-s.Recompute.ReplayedM) > 1e-3 || math.Abs(replay.GapM-s.Recompute.GapM) > 1e-3 {
				t.Errorf("replay %.4f m, gaps %.4f m; reference %.4f m, %.4f m",
					replay.SmoothedM, replay.GapM, s.Recompute.ReplayedM, s.Recompute.GapM)
			}
			// Nothing is credited across a close: the cumulative the bests
			// are measured on stands still from a segment's last fix to the
			// next one's first.
			for k := 1; k < len(first); k++ {
				if a, b := replay.SmoothedCumM[first[k]-1], replay.SmoothedCumM[first[k]]; a != b {
					t.Errorf("segment %d: the cumulative moves %.3f m across the close", k, b-a)
				}
			}

			meta := fmt.Sprintf(`{"distance_step_filled_m":%v,"distance_step_over_chord_m":%v,"distance_segments":%d}`,
				s.Expected.StepDistanceM, s.Expected.StepOverChordM, len(s.Segments))
			got, _ := recomputeWatchTrack(t, meta, track)
			if math.Abs(got-s.Expected.DistanceM) > 0.005+1e-3 {
				t.Errorf("recomputed %.2f m, the recorder credited %.3f m", got, s.Expected.DistanceM)
			}

			unmarked, _ := s.storedTrack(false)
			old := replayRecordedTrack(unmarked, 10)
			if old.Segments != 1 ||
				math.Abs(old.SmoothedM-s.Recompute.UnmarkedReplayedM) > 1e-3 ||
				math.Abs(old.GapM-s.Recompute.UnmarkedGapM) > 1e-3 {
				t.Errorf("unmarked: %d segments, %.4f m, gaps %.4f m; reference one stream %.4f m, %.4f m",
					old.Segments, old.SmoothedM, old.GapM, s.Recompute.UnmarkedReplayedM, s.Recompute.UnmarkedGapM)
			}
			lost, _ := recomputeWatchTrack(t, meta, unmarked)
			if math.Abs(lost-s.Recompute.UnmarkedDistanceM) > 0.005+1e-3 {
				t.Errorf("marks lost: recomputed %.2f m, want the run-total rule's %.3f m", lost, s.Recompute.UnmarkedDistanceM)
			}
			if s.Expected.StepOverChordM > 0 && lost > s.Expected.DistanceM+0.005 {
				t.Errorf("marks lost: recomputed %.2f m, past the recorder's %.3f m", lost, s.Expected.DistanceM)
			}
		})
	}
	for name := range want {
		found := false
		for _, s := range segmentedRuns(t) {
			found = found || s.Name == name
		}
		if !found {
			t.Errorf("vector %s is gone from segmentedRuns; the test lost its case", name)
		}
	}
}

// A mark on a point the replay cannot place (no timestamp) starts the segment
// at the next point that has one, rather than being lost with it.
func TestReplayRecordedTrack_SegmentMarkOnAnUntimestampedPointCarriesToTheNext(t *testing.T) {
	var s segmentedRun
	for _, r := range segmentedRuns(t) {
		if r.Name == "segments_pause_moved" {
			s = r
		}
	}
	if s.Name == "" {
		t.Fatal("segments_pause_moved is gone from segmentedRuns")
	}
	track, first := s.storedTrack(false)
	lat, lng := *track[first[1]].Lat, *track[first[1]].Lng
	withMark := append([]RecordedTrackPoint{}, track[:first[1]]...)
	withMark = append(withMark, RecordedTrackPoint{Lat: &lat, Lng: &lng, SegmentStart: true})
	withMark = append(withMark, track[first[1]:]...)
	replay := replayRecordedTrack(withMark, 10)
	if replay.Segments != 2 || math.Abs(replay.SmoothedM-s.Recompute.ReplayedM) > 1e-3 {
		t.Errorf("%d segments, %.4f m; want 2, %.4f m", replay.Segments, replay.SmoothedM, s.Recompute.ReplayedM)
	}
	if replay.Positions[first[1]] != nil {
		t.Error("the untimestamped point was given a position")
	}
}
