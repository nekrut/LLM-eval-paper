#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

process_sample() {
    local sample=$1
    local r1="data/raw/${sample}_1.fq.gz"
    local r2="data/raw/${sample}_2.fq.gz"
    [ -f "$r1" ] && [ -f "$r2" ] || return 0

    local base="results/${sample}"
    local bam="${base}.bam"
    local bai="${base}.bai"

    # Skip if BAM and BAI already exist
    if [ -f "$bam" ] && [ -f "$bai" ]; then
        return 0
    fi

    # Align with BWA MEM, sort, index
    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" |
        samtools view -@ 4 -b - |
        samtools sort -o "$bam"
    samtools index "$bam"

    # Variant calling with lofreq
    lofreq call --ref data/ref/chrM.fa \
                --bam "$bam" \
                --output "${base}.vcf.gz" \
                --min-qual 20

    # Index VCF
    bgzip -@ 4 "${base}.vcf.gz"
    tabix -p vcf "${base}.vcf.gz"

    # Extract fields with SnpSift and format for collapsed.tsv
    local vcf="${base}.vcf.gz"
    local tbi="${base}.vcf.gz.tbi"

    # Ensure results/collapsed.tsv exists; write header if new
    local out="results/collapsed.tsv"
    if [ ! -f "$out" ]; then
        echo -e "sample\tchrom\tpos\tref\talt\taf" > "$out"
    fi

    # Process each variant record and append to collapsed.tsv
    zcat "$vcf" |
        SnpSift extractFields -s '\t' \
            CHROM,POS,REF,ALT,INFO/AF \
            - |
        awk -v s="$sample" '{print s"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}' >> "$out"
}

# Process all samples
for samp in M117-bl M117-ch M117C1-bl M117C1-ch; do
    process_sample "$samp"
done

exit 0