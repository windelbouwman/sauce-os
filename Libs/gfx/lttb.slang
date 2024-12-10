
# Largest Triangle Three Bucket (LTTB) algorithm

from datatypes import List
from math import floor, fabs
from chart import DataPoint

pub fn lttb(values: List[DataPoint], threshold: int) -> List[DataPoint]:
    # Create a selection of data points for plotting.
    # Divide the data into buckets, and from each bucket
    # select a point such that this point forms the largest
    # triangle with its two neighbour points.
    if threshold == 0:
        return values

    let data_length: int = values.len()
    if threshold >= data_length:
        return values
    
    let bucket_size: float = float(data_length - 2) / float(threshold - 2)
    let sampled: List[DataPoint] = List()

    # Always add first point:
    let p1 = values.first()
    sampled.append(p1)

    # Loop over the buckets:
    let i = 0
    while i < threshold - 2:
        # Determine indici of bucket 2 and 3:
        let start2: int = int(floor((i + 0) * bucket_size)) + 1
        let end2: int = int(floor((i + 1) * bucket_size)) + 1
        let count2: int = end2 - start2

        let start3: int = end2
        let end3: int = int(floor((i + 2) * bucket_size)) + 1
        if end3 > data_length:
            end3 = data_length
        let count3: int = end3 - start3

        # Calculate point average of bucket 3 (next):
        let avg_x = 0.0
        let avg_y = 0.0
        let j = start3
        while j < end3:
            let p3 = values[j]
            avg_x += p3.x
            avg_y += p3.y
            j += 1
        avg_x /= count3
        avg_y /= count3

        # Pick point that makes maximum triangle from bucket 2 (current):
        j = start2
        let maxAreaPoint = values[j]
        let maxArea = -1.0
        while j < end2:
            let p2 = values[j]
            let area = fabs((p1.x - avg_x) * (p2.y - p1.y) - (p1.x - p2.x) * (avg_y - p1.y)) * 0.5
            if area > maxArea:
                maxAreaPoint = p2
                maxArea = area
            j += 1
        sampled.append(maxAreaPoint)

        # For the next loop:
        p1 = maxAreaPoint
        i += 1

    # Always add last point:
    sampled.append(values.last())

    sampled
