local magtooltips = {}

magtooltips.MATCH_TARGET_BUTTON = 'Starts AudioGuide concatenation\nwith selected item as target.'

magtooltips.BUILD_CORPUS_BUTTON = 'Starts AudioGuide segmentation building\nCorpus with selected items.'

magtooltips.MINMAXIMIZE = 'Reduce/Restore the window size showing/hiding the parameters.'

magtooltips.PREFERENCES = 'Show/hide the preferences window.'

magtooltips.TARGET_SF_PARAMS_HEADER = 'Show/hide the target sound file parameters.'

magtooltips.SEG_ARG_HEADER = 'Show/hide the segmentation arguments.'

magtooltips.CORPUS_PARAMS_HEADER = 'Show/hide the Corpus parameters.'

magtooltips.SUPERIMPOSE_PARAMS_HEADER = 'Show/hide the Superimpose parameters.'

magtooltips.SEARCH_PASS_HEADER = 'Show/hide the Search Passes configurator.'

magtooltips.TSF_THRESHOLD = 'Onset trigger threshold value in dB.\nWhen the soundfile\'s amplitude rises above the threshold, a segment onset is created.\nHigher values closer to 0 will lead to fewer onsets.'

magtooltips.TSF_OFFSET_RISE = 'Offset rise ratio.\nIt causes an offset when the ampltiude of the soundfile in\nthe next frame divded by the amplitude of the current frame\nis greater than or equal to this ratio.\nTherefore if you are in a current sound segment but the soundfile\nsuddenly gets much louder, the current segment ends.'

magtooltips.TSF_MIN_SEG_LEN = 'The minimum duration in seconds of a target segment.'

magtooltips.TSF_MAX_SEG_LEN = 'The maximum duration in seconds of a target segment.'

magtooltips.SEG_THRESHOLD = magtooltips.TSF_THRESHOLD

magtooltips.SEG_OFFSET_RISE = magtooltips.TSF_OFFSET_RISE

magtooltips.SEG_MULTI_RISE = 'Turns on the segmentation multirise feature.\nEssentially this creates a larger number of corpus segments which can overlap each other.\nWhen this flag is present the segmentation algorithm will loop over the\ncorpus soundfile several times, varying the user supplied riseRatio (-r) +/- 20%.\nThis leads to certain segments will start at the same time, but last different durations.'

magtooltips.CGA_RESTRICT_OVERLAPS = 'An integer specifying how many overlapping samples may be\nchosen by the concatenative algorithm at any given moment.'

magtooltips.CGA_ONSET_LEN = 'Fade-in time in percentage of duration for any choosen corpus segment.'

magtooltips.CGA_OFFSET_LEN = 'Fade-out time in percentage of duration for any choosen corpus segment.'

magtooltips.CGA_LIMIT_DUR = 'Limits the duration of each choosen segment.\nThe duration of Target and Corpus over this value (in seconds) will be truncated.\nThis happens before concatenation.'

magtooltips.CGA_ALLOW_REPETITION = 'If False, any of the segments from this corpus may only be picked one time.\nIf True there is no restriction.'

magtooltips.CGA_RESTRICT_REPETITION = 'A delay time in seconds where, once chosen, a segment from this\ncorpus entry is invalid to be picked again.\nThe default is 0.5, which prevent the same corpus segment\nfrom being selected in quick succession.'

magtooltips.CGA_CLIP_DUR_TO_TARGET = 'The duration of any selected sounds from this CORPUS will\nbe truncated by the duration of the target.\nThis happens after concatenation.'

magtooltips.ALIGN_PEAKS = 'Aligns the peak times of corpus segments to match those of the target segments.\nThus, every corpus segment selected to represent a target segment will be\nmoved in time such that corpus segment\'s peak amplitude is\naligned with the target segment\'s.'

magtooltips.SI_MIN_SEG = 'The minimum number of corpus segments that must be chosen to match a target segment.'

magtooltips.SI_MAX_SEG = 'The maximum number of corpus segments that must be chosen to match a target segment.'

magtooltips.SI_MIN_FRAME = 'The minimum number of corpus segments that must be chosen to begin at any single moment in time. (10ms)'

magtooltips.SI_MAX_FRAME = 'The maximum number of corpus segments that must be chosen to begin at any single moment in time. (10ms)'

magtooltips.SI_MIN_OVERLAP = 'The minimum number of overlapping corpus segments at any single moment in time.'

magtooltips.SI_MAX_OVERLAP = 'The maximum number of overlapping corpus segments at any single moment in time.'

magtooltips.SI_ENABLE_MIN_SEG = 'Enable/Disable'

magtooltips.SI_ENABLE_MAX_SEG = 'Enable/Disable'

magtooltips.SI_ENABLE_MIN_FRAME = 'Enable/Disable'

magtooltips.SI_ENABLE_MAX_FRAME = 'Enable/Disable'

magtooltips.SI_ENABLE_MIN_OVERLAP = 'Enable/Disable'

magtooltips.SI_ENABLE_MAX_OVERLAP = 'Enable/Disable'

magtooltips.SPASS_MODE = 'Allows you to select the desired output for this search step.'

magtooltips.DESCRIPTOR = 'Allow to select the search criterion with which to analyze the segments.'

magtooltips.ADD_DESCRIPTOR = 'Add another descriptor to this search pass.'

magtooltips.REMOVE_DESCRIPTOR = 'Remove the last descriptor from this search pass.'

magtooltips.ADD_SPASS = 'Add a search pass.'

magtooltips.REMOVE_SPASS = 'Remove the last search pass.'

magtooltips.SPASS_PERCENTAGE = 'The percentage of the best segments found (based on the descriptors) that go to the next search step.'

magtooltips.PREF_SET_ENV_PATH = 'Set the path of the necessary environment for operation.\nYou can download and install it by clicking on Download Environment.'

magtooltips.PREF_DOWNLOAD_ENV = 'Download the preconfigured environment to use the Reaper AudioGuide Interface.'

magtooltips.PREF_OVERRIDE_AG_PATH = 'You can specify the path of AudioGuide if you want to use a specific version.'

magtooltips.PREF_OVERRIDE_PYTHON_PATH = 'You can specify the path of Python3 if you want to use a specific version.'


return magtooltips