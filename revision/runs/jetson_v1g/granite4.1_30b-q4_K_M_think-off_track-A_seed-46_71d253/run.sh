#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# 2. Reference indexing (once, idempotent)
if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "$REF.bwt" ]]; then
    bwa index "$REF"
fi

process_sample() {
    local sample=$1
    local bam="$RESULTS/${sample}.bam"
    local bam_bai="${bam}.bai"
    local vcf_uncompressed="$RESULTS/${sample}.vcf"
    local vcf_gz="${vcf_uncompressed}.gz"
    local vcf_tbi="${vcf_gz}.tbi"

    # 3. Alignment (skip if final VCF already exists and is up‑to‑date)
    if [[ -f "$vcf_tbi" && "$vcf_tbi" -nt "data/raw/${sample}_1.fq.gz" && "$vcf_tbi" -nt "data/raw/${sample}_2.fq.gz" ]]; then
        return 0
    fi

    # bwa mem with explicit \t (not real tab)
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" \
        "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
    samtools sort -@ "$THREADS" -o "$bam"

    # 5. Index BAM
    if [[ ! -f "$bam_bai" || "$bam_bai" -ot "$bam" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # 6. Variant calling with lofreq (skip if VCF already exists and up‑to‑date)
    if [[ -f "$vcf_tbi" && "$vcf_tbi" -nt "$bam" ]]; then
        return 0
    fi
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out "$vcf_uncompressed" \
        "$bam"

    # 7. Compress and index VCF, cleanup uncompressed version
    if [[ ! -f "$vcf_gz" || "$vcf_gz" -ot "$vcf_uncompressed" ]]; then
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        rm "$vcf_uncompressed"
    fi
    if [[ ! -f "$vcf_tbi" || "$vcf_tbi" -ot "$vcf_gz" ]]; then
        tabix -p vcf "$vcf_gz"
    fi
}

# Process each sample in parallel respecting THREADS limit
export -f process_sample
export THREADS SAMPLES RESULTS
seq 0 $((THREADS-1)) | parallel -j "$THREADS" \
    bash -c 'for s in "${SAMPLES[@]}"; do process_sample "$s"; done'

# 8. Collapse step (rebuild if any VCF is newer than collapsed.tsv)
COLLAPSED="$RESULTS/collapsed.tsv"
if [[ ! -f "$COLLAPSED" || "$(find "${SAMPLES[@]/%/.vcf.gz}" | xargs -I{} stat -c %Y {} | sort -n | tail -1)" -gt "$(stat -c %Y "$COLLAPSED")" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for s in "${SAMPLES[@]}"; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS/${s}.vcf.gz" | while read -r chrom pos ref alt af; do
                echo -e "${s}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
            done
        done
    } > "$COLLAPSED"
fi