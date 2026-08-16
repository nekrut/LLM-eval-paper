#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Function to process a sample given R1 and R2 fastq files
process_sample() {
    local base=$1
    local r1=$2
    local r2=$3
    local bam=results/${base}.bam
    local bai=results/${base}.bam.bai
    local vcf=results/${base}.vcf.gz
    local tbi=results/${base}.vcf.gz.tbi

    # Skip if all outputs exist (idempotent)
    if [[ -s "${bam}" && -s "${bai}" && -s "${vcf}" && -s "${tbi}" ]]; then
        return 0
    fi

    # Create temporary directory for this sample's intermediate files
    local workdir=$(mktemp -d)
    trap "rm -rf '${workdir}'" EXIT

    # Align with bwa-mem, sort and index with samtools
    bwa mem -t 4 data/ref/chrM.fa "${workdir}/${base}_1.fq.gz" "${workdir}/${base}_2.fq.gz" |
        samtools view -@ 4 -b - > "${workdir}/alignments.bam"
    samtools sort -o "${bam}" "${workdir}/alignments.bam"
    samtools index "${bam}"

    # Preprocess with lofreq
    lofreq depth --no-trim --min-base-quality 20 --min-mapq 30 \
        -r chrM.fa -i "${bam}" -o "${workdir}/depth.txt" "${base}_1.fq.gz" "${base}_2.fq.gz"

    # Variant calling with lofreq
    lofreq call --no-trim --min-base-quality 20 --min-mapq 30 \
        -r chrM.fa -i "${bam}" -o "${workdir}/lofreq.vcf" "${base}_1.fq.gz" "${base}_2.fq.gz"

    # Filter with bcftools and annotate with SnpSift
    bcftools view -i 'QUAL>30 && DP>10' -Oz -o "${vcf}" "${workdir}/lofreq.vcf"
    tabix -p vcf "${vcf}"

    # Collapse per-sample VCF entries into a single table row (sample, chrom, pos, ref, alt, af)
    awk -v sample="${base}" '
        BEGIN { OFS="\t"; print "sample", "chrom", "pos", "ref", "alt", "af" }
        {
            split($8, GT, /[|:]/);  # get genotype field
            ref=substr($4,1,1);
            alt=$5;
            pos=$2;
            chrom=$1;
            af=$10;  # allele frequency from INFO/AF
            print sample, chrom, pos, ref, alt, af
        }' <(zcat "${vcf}") >> results/collapsed.tsv

    # Ensure header is written only once (first sample processed)
    if [[ ! -s results/collapsed.tsv ]]; then
        echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    fi
}

# Process each sample pair
process_sample M117-bl  data/raw/M117-bl_1.fq.gz  data/raw/M117-bl_2.fq.gz
process_sample M117-ch  data/raw/M117-ch_1.fq.gz   data/raw/M117-ch_2.fq.gz
process_sample M117C1-bl data/raw/M117C1-bl_1.fq.gz data/raw/M117C1-bl_2.fq.gz
process_sample M117C1-ch data/raw/M117C1-ch_1.fq.gz  data/raw/M117C1-ch_2.fq.gz

# Ensure collapsed.tsv has header (if not already added by awk)
if ! head -n1 results/collapsed.tsv | grep -q '^sample'; then
    sed -i '1i sample\tchrom\tpos\tref\talt\taf' results/collapsed.tsv
fi

# Index the collapsed table with tabix for downstream use (optional)
tabix -p tsv results/collapsed.tsv || true  # ignore if already indexed or not needed

exit 0