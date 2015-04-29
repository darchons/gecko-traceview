# jshint devel:true

re_grouping = /\D+|\d+(\.\d+)?[ETGMkmμnpf]?/g

# Smart comparison function used with Array.prototype.sort. It is able to compare numbers
# and suffixes by value rather than by character. For example, '1MB' will come before '1GB',
# and 'v10' will come after 'v9'.
smartSort = (str1, str2) ->
    match1 = (str1 + '').match re_grouping
    match2 = (str2 + '').match re_grouping

    for i in [0...Math.min match1.length, match2.length]
        if !isNaN(parseInt match1[i]) and !isNaN(parseInt match2[i])
            diff = revSmartPrefix(match1[i]) - revSmartPrefix(match2[i])
            return diff if diff != 0
            continue
        m1 = match1[i].toUpperCase()
        m2 = match2[i].toUpperCase()
        return -1 if m1 < m2
        return 1 if m1 > m2

    match1.length - match2.length

# Same as smartSort but reversed
revSmartSort = (str1, str2) -> (-smartSort str1, str2)

_smartUnits = (values, names, precisions) ->
    (value) ->
        for i in [0...values.length]
            continue if value < values[i]
            return (value / values[i]).toPrecision(
                precisions[Math.min precisions.length - 1, i]) + names[i]
        value.toPrecision precisions[precisions.length - 1]

_revSmartUnits = (values, names) ->
    (value) ->
        value = value + ''
        for i in [0...values.length]
            continue if value.indexOf(names[i], value.length - names[i].length) < 0
            return +(value.slice 0, value.length - names[i].length) * values[i]
        parseFloat value

# Format a floating-point number by adding the appropriate SI-prefix and rounding to
# appropriate digits. e.g. smartPrefix(0.001) === '1m'
smartPrefix = _smartUnits(
    [1e15, 1e12, 1e9, 1e6, 1e3, 1, 1e-3, 1e-6, 1e-9, 1e-12, 1e-15]
    ['E', 'T', 'G', 'M', 'k', '', 'm', 'μ', 'n', 'p', 'f', '']
    [3])

# Parse a string of a number with SI-prefix into its equivalent floating-point number.
# e.g. revSmartPrefix('1m') === 0.001
revSmartPrefix = _revSmartUnits(
    [1e15, 1e12, 1e9, 1e6, 1e3, 1e-3, 1e-6, 1e-9, 1e-12, 1e-15, 1]
    ['E', 'T', 'G', 'M', 'k', 'm', 'μ', 'n', 'p', 'f', ''])

# Format a number of seconds into appropriate time units. e.g. smartTime(3600) === '1h'
smartTime = _smartUnits(
    [31556952, 604800, 86400, 3600, 60, 1, 1e-3, 1e-6, 1e-9, 1e-12]
    ['y', 'w', 'd', 'h', 'm', 's', 'ms', 'μs', 'ns', 'ps', '']
    [2, 2, 2, 2, 2, 2, 3])

# Format a fraction number into a percentage. e.g. smartPercent(0.1) === '10.0%'
smartPercent = (v) -> ((v * 100).toPrecision(3) + "%")

binarySearch = (arr, value, fn) ->
    fn ?= (v) -> v
    [lo, hi] = [0, arr.length]
    i = Math.floor (lo + hi) / 2
    [iv, ivp1] = [fn(arr[i]), fn(arr[i + 1])]
    until iv < value and not (ivp1 < value)
        lo = i + 1 if ivp1 < value
        hi = i if not (iv < value)
        return hi if lo >= hi
        i = Math.floor (lo + hi) / 2
        [iv, ivp1] = [fn(arr[i]), fn(arr[i + 1])]
    i + 1

drawn_frames = []

setLimits = (slider, trace) ->
    min = trace.times[0]
    max = trace.times[trace.times.length - 1]

    slider.rangeSlider
        bounds:
            min: min
            max: max
        defaultValues:
            min: min
            max: max / 2
        range:
            min: 0.2
        formatter: (value) -> (Math.round(value * 1000) + "ms")
        valueLabels: "change"

redraw = (plot, trace, range) ->
    min = range.min # time at start of view
    duration = range.max - range.min # time duration inside view
    start = binarySearch trace.times, min # index of frame that first starts in view
    end = binarySearch trace.times, range.max # index of frame that last ends in view

    WIDTH = plot.width()
    HEIGHT = plot.height()
    FRAME_STRIDE = HEIGHT / 16
    FRAME_HEIGHT = FRAME_STRIDE * 0.8
    MIN_FRAME_WIDTH = 2 / WIDTH

    active_stack = [] # unfinished frames
    active_count = 0 # number of active frames in active_stack
    mergeable_frames = [] # finished frames waiting to be merged
    drawn_frames = []

    ctx = plot.clearCanvas()

    _drawFrame = (frame) ->
        x = WIDTH * frame.left
        y = HEIGHT - (frame.top + 1) * FRAME_STRIDE
        width = WIDTH * (frame.right - frame.left)
        height = FRAME_HEIGHT
        color = chroma.hsl(
            222 - 222 * Math.atan((frame.multiplicity or 0) / 20) * 2 / Math.PI, 0.55, 0.55)

        ctx.drawRect
            x: x
            y: y
            width: width
            height: height
            fillStyle: color.hex()
            strokeWidth: 1
            strokeStyle: color.darken().hex()
            fromCenter: false

        drawn_frames.push
            left: x
            right: x + width
            top: y
            bottom: y + height
            label: (if not frame.multiplicity then frame.label else
                "#{frame.multiplicity} labels<br>(#{frame.label}, etc)") +
                "<br>spanning #{Math.round((frame.right - frame.left) * duration * 1000)}ms"

        if not frame.multiplicity and width > 4 * MIN_FRAME_WIDTH
            textOptions =
                fillStyle: "#fff"
                strokeWidth: 0
                fontSize: "1em"
                text: frame.label
                fromCenter: false
            textDims = ctx.measureText textOptions
            if textDims.width + 2 * MIN_FRAME_WIDTH <= width
                textOptions.x = x + (width - textDims.width) / 2
                textOptions.y = y + (height - textDims.height) / 2
                ctx.drawText textOptions

    # prefill with frames that started to the left of view
    for i in [0...start] by 1
        label = trace.labels[i]
        if not label.length
            # popping a frame; discard from active stack
            active_count--
            continue
        # pushing an unfinished frame
        active_stack.push null while active_count >= active_stack.length
        active_stack[active_count] =
            label: label
            left: 0
            right: 0
            top: active_count
        active_count++

    # draw frames within view
    for i in [start...end] by 1
        label = trace.labels[i]
        pos = (trace.times[i] - min) / duration
        if label.length
            # push an unfinished frame onto stack
            active_stack.push null while active_count >= active_stack.length
            active_stack[active_count] =
                label: label
                left: pos
                right: 0
                top: active_count
            active_count++
            continue

        # popping a frame; finish the frame
        active_count--
        frame = active_stack[active_count]
        frame.right = pos

        if pos - frame.left < MIN_FRAME_WIDTH
            # save for merging later
            mergeable_frames.push null while active_count >= mergeable_frames.length
            merger = mergeable_frames[active_count]
            if frame.left - merger?.right < MIN_FRAME_WIDTH
                # merge with previous frame
                merger.right = pos
                merger.multiplicity = (merger.multiplicity or 0) + 1
                continue

            if merger and merger.right - merger.left >= MIN_FRAME_WIDTH
                # draw the merged frame
                _drawFrame merger
            # replace previous unmerged frame
            mergeable_frames[active_count] = frame
            continue

        # draw now
        _drawFrame frame

    # finish all remaining frames
    for merger in mergeable_frames
        if merger and merger.right - merger.left >= MIN_FRAME_WIDTH
            _drawFrame merger

    while active_count-- > 0
        frame = active_stack[active_count]
        frame.right = 1
        _drawFrame frame

    drawn_frames.sort (a, b) -> a.right - b.right

initialize = (trace) ->
    plot = $(".traceview>.plot")
    slider = $(".traceview>.slider")
    plot.attr "width", slider.width() # also clears the canvas

    setLimits slider, trace
    redraw plot, trace, slider.rangeSlider "values"
    slider.on "valuesChanging", (e, data) ->
        redraw plot, trace, data.values

    tooltip = $(".tooltip")
    mousemove = (e) ->
        plotOffset = plot.offset()
        [x, y] = [e.pageX - plotOffset.left, e.pageY - plotOffset.top]
        start = binarySearch drawn_frames, x, (f) -> f?.right

        for i in [start...drawn_frames.length] by 1
            frame = drawn_frames[i]
            if x <= frame.left or y <= frame.top or y > frame.bottom
                continue
            tooltip.children(".tooltip-inner").html frame.label
            tooltip.addClass("in").offset(
                left: plotOffset.left + (frame.right + frame.left - tooltip.width()) / 2
                top: plotOffset.top + frame.top - tooltip.height() - 20)
            return
        tooltip.removeClass "in"
    mouseout = (e) ->
        tooltip.removeClass "in"

    plot.mousemove mousemove
    tooltip.mousemove mousemove
    plot.mouseout mouseout

$ ->
    $.getJSON "trace.json"
        .done (trace) -> initialize(trace)
