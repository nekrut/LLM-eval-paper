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

    # 3. bwa mem → sorted BAM
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
    samtools sort -@ "$THREADS" -o "$bam"

    # 5. Index BAM
    if [[ ! -f "$bam_bai" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # 6. lofreq variant calling (uncompressed VCF)
    if [[ ! -f "$vcf_uncompressed" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "$vcf_uncompressed" \
            "$bam"
    fi

    # 7. Compress & index VCF (skip if already done)
    if [[ ! -f "$vcf_tbi" || "$vcf_tbi" -ot "$vcf_uncompressed" ]]; then
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
}

# Process each sample in parallel respecting THREADS limit
export -f process_sample
export THREADS SAMPLES REF RESULTS
seq 0 $((THREADS-1)) | parallel -j "$THREADS" '
    i=$((THREADS*$JOB+$THREAD))
    if [[ $i -lt ${#SAMPLES[@]} ]]; then
        sample=${SAMPLES[$i]}
        process_sample "$sample"
    fi
'

# 8. Collapse step (rebuild only if any VCF is newer than collapsed.tsv)
COLLAPSED="$RESULTS/collapsed.tsv"
if [[ ! -f "$COLLAPSED" || "$COLLAPSED" -ot "${SAMPLES[@]/%/.vcf.gz}" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS/${sample}.vcf.gz" | \
                awk -v s="$sample" '{print s "\t" $0}'
        done
    } > "$COLLAPSED"
fi